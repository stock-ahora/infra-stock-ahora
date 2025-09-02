
# ---------- Lambda code (Python) ----------
# Escribimos el archivo Python y luego lo zipeamos.
resource "local_file" "lambda_py" {
  filename = "${path.module}/lambda_src/main.py"
  content  = <<-PY
import os, json, logging, boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
rds = boto3.client("rds")
asg = boto3.client("autoscaling")
ecs = boto3.client("ecs")
appscaling = boto3.client("application-autoscaling")

# Tags donde guardamos estado previo para restaurar en "on"
TAG_PREV_DESIRED = "PowerSwitchPrevDesired"
TAG_PREV_MIN     = "PowerSwitchPrevMin"
TAG_SVC_PREV_DESIRED = "PowerSwitchPrevDesired"

def unique(seq):
    return list(dict.fromkeys(seq))

# ----------------- Helpers ASG/Lifecycle/ECS -----------------
def asg_instance_ids(g):
    return [i.get("InstanceId") for i in g.get("Instances", []) if i.get("InstanceId")]

def disable_instance_protection(asg_name, instance_ids):
    if not instance_ids:
        return
    asg.set_instance_protection(
        AutoScalingGroupName=asg_name,
        InstanceIds=instance_ids,
        ProtectedFromScaleIn=False
    )

def list_asgs():
    groups = []
    paginator = asg.get_paginator("describe_auto_scaling_groups")
    for page in paginator.paginate():
        groups.extend(page.get("AutoScalingGroups", []))
    return groups

def get_asgs_by_names(names):
    if not names:
        return []
    names = [n.strip() for n in names.split(",") if n.strip()]
    groups = []
    for i in range(0, len(names), 50):
        resp = asg.describe_auto_scaling_groups(AutoScalingGroupNames=names[i:i+50])
        groups.extend(resp.get("AutoScalingGroups", []))
    return groups

def get_asgs_by_tags(tags):
    if not tags:
        return []
    res = []
    for g in list_asgs():
        kv = {t["Key"]: t["Value"] for t in g.get("Tags", [])}
        if all(k in kv and kv[k] == v for k, v in tags.items()):
            res.append(g)
    return res

def tag_asg(asg_name, key, value):
    asg.create_or_update_tags(Tags=[{
        "ResourceId": asg_name,
        "ResourceType": "auto-scaling-group",
        "Key": key, "Value": str(value), "PropagateAtLaunch": False
    }])

def get_tag(g, key):
    for t in g.get("Tags", []):
        if t["Key"] == key:
            return t.get("Value")
    return None

def list_lifecycle_hooks(asg_name):
    try:
        resp = asg.describe_lifecycle_hooks(AutoScalingGroupName=asg_name)
        return resp.get("LifecycleHooks", [])
    except Exception:
        return []

def complete_lifecycle_continue(asg_name, hook_name, instance_id):
    asg.complete_lifecycle_action(
        AutoScalingGroupName=asg_name,
        LifecycleHookName=hook_name,
        LifecycleActionResult="CONTINUE",
        InstanceId=instance_id,
    )

def list_ecs_clusters():
    arns, next_token = [], None
    while True:
        kwargs = {"maxResults": 100}
        if next_token:
            kwargs["nextToken"] = next_token
        resp = ecs.list_clusters(**kwargs)
        arns.extend(resp.get("clusterArns", []))
        next_token = resp.get("nextToken")
        if not next_token: break
    return arns

def clusters_by_names(names):
    if not names: return []
    wanted = [n.strip() for n in names.split(",") if n.strip()]
    if not wanted: return []
    arns = list_ecs_clusters()
    desc = ecs.describe_clusters(clusters=arns)
    return [c["clusterArn"] for c in desc.get("clusters", []) if c.get("clusterName") in wanted]

def clusters_by_tags(tags):
    if not tags: return []
    arns = list_ecs_clusters()
    res = []
    for arn in arns:
        t = ecs.list_tags_for_resource(resourceArn=arn).get("tags", [])
        kv = {x["key"]: x["value"] for x in t}
        if all(k in kv and kv[k] == v for k, v in tags.items()):
            res.append(arn)
    return res

def list_services(cluster_arn):
    arns, next_token = [], None
    while True:
        kwargs = {"cluster": cluster_arn, "maxResults": 100}
        if next_token: kwargs["nextToken"] = next_token
        resp = ecs.list_services(**kwargs)
        arns.extend(resp.get("serviceArns", []))
        next_token = resp.get("nextToken")
        if not next_token: break
    return arns

def filter_services_by_prefix(cluster_arn, prefix):
    svcs = list_services(cluster_arn)
    if not prefix: return svcs
    res = []
    for i in range(0, len(svcs), 10):
        chunk = svcs[i:i+10]
        desc = ecs.describe_services(cluster=cluster_arn, services=chunk)
        for s in desc.get("services", []):
            if s.get("serviceName", "").startswith(prefix):
                res.append(s["serviceArn"])
    return res

def get_service_tags(svc_arn):
    tags = ecs.list_tags_for_resource(resourceArn=svc_arn).get("tags", [])
    return {t["key"]: t["value"] for t in tags}

def put_service_tag(svc_arn, key, value):
    ecs.tag_resource(resourceArn=svc_arn, tags=[{"key": key, "value": str(value)}])

def update_service_desired(cluster_arn, svc_arn, desired):
    name = svc_arn.split("/")[-1]
    ecs.update_service(cluster=cluster_arn, service=name, desiredCount=int(desired))

def tune_app_autoscaling(cluster_arn, svc_arn, min_cap, max_cap):
    svc_name = svc_arn.split("/")[-1]
    cluster_name = cluster_arn.split("/")[-1]
    resource_id = f"service/{cluster_name}/{svc_name}"
    appscaling.register_scalable_target(
        ServiceNamespace="ecs",
        ResourceId=resource_id,
        ScalableDimension="ecs:service:DesiredCount",
        MinCapacity=int(min_cap),
        MaxCapacity=int(max_cap),
    )

def container_instance_arn_for_ec2(cluster_arn_or_name, ec2_instance_id):
    arns, next_token = [], None
    while True:
        kw = {"cluster": cluster_arn_or_name}
        if next_token: kw["nextToken"] = next_token
        resp = ecs.list_container_instances(**kw)
        arns.extend(resp.get("containerInstanceArns", []))
        next_token = resp.get("nextToken")
        if not next_token: break
    for i in range(0, len(arns), 10):
        desc = ecs.describe_container_instances(cluster=cluster_arn_or_name, containerInstances=arns[i:i+10])
        for ci in desc.get("containerInstances", []):
            if ci.get("ec2InstanceId") == ec2_instance_id:
                return ci.get("containerInstanceArn")
    return None

def drain_and_deregister_container_instance(cluster_arn_or_name, container_instance_arn):
    try:
        ecs.update_container_instances_state(
            cluster=cluster_arn_or_name,
            containerInstances=[container_instance_arn],
            status="DRAINING"
        )
    except Exception as e:
        logger.info("Update to DRAINING failed or not needed: %s", str(e))
    try:
        ecs.deregister_container_instance(
            cluster=cluster_arn_or_name,
            containerInstance=container_instance_arn,
            force=True
        )
    except Exception as e:
        logger.info("Deregister container instance failed or not needed: %s", str(e))

# ----------------- Descubrimiento EC2/RDS -----------------
def get_all_ec2_ids():
    ids = []
    paginator = ec2.get_paginator("describe_instances")
    for page in paginator.paginate():
        for r in page.get("Reservations", []):
            for inst in r.get("Instances", []):
                st = (inst.get("State", {}) or {}).get("Name")
                if st not in ("shutting-down", "terminated"):
                    ids.append(inst["InstanceId"])
    return unique(ids)

def get_ec2_by_tags(tags):
    if not tags: return []
    filters = [{"Name": f"tag:{k}", "Values": [v]} for k, v in tags.items()]
    ids = []
    paginator = ec2.get_paginator("describe_instances")
    for page in paginator.paginate(Filters=filters):
        for r in page.get("Reservations", []):
            for inst in r.get("Instances", []):
                st = (inst.get("State", {}) or {}).get("Name")
                if st not in ("shutting-down", "terminated"):
                    ids.append(inst["InstanceId"])
    return unique(ids)

def get_all_rds_instances():
    ids = []
    paginator = rds.get_paginator("describe_db_instances")
    for page in paginator.paginate():
        for db in page.get("DBInstances", []):
            ids.append(db["DBInstanceIdentifier"])
    return unique(ids)

def get_all_rds_clusters():
    ids = []
    paginator = rds.get_paginator("describe_db_clusters")
    for page in paginator.paginate():
        for cl in page.get("DBClusters", []):
            ids.append(cl["DBClusterIdentifier"])
    return unique(ids)

def get_rds_by_tags(tags):
    if not tags: return [], []
    inst_ids, clus_ids = [], []
    paginator = rds.get_paginator("describe_db_instances")
    for page in paginator.paginate():
        for db in page.get("DBInstances", []):
            arn = db["DBInstanceArn"]
            t = rds.list_tags_for_resource(ResourceName=arn)["TagList"]
            kv = {x["Key"]: x["Value"] for x in t}
            if all(k in kv and kv[k] == v for k, v in tags.items()):
                inst_ids.append(db["DBInstanceIdentifier"])
    paginator = rds.get_paginator("describe_db_clusters")
    for page in paginator.paginate():
        for cl in page.get("DBClusters", []):
            arn = cl["DBClusterArn"]
            t = rds.list_tags_for_resource(ResourceName=arn)["TagList"]
            kv = {x["Key"]: x["Value"] for x in t}
            if all(k in kv and kv[k] == v for k, v in tags.items()):
                clus_ids.append(cl["DBClusterIdentifier"])
    return unique(inst_ids), unique(clus_ids)

# ----------------- EC2 helpers -----------------
def split_spot_and_ondemand(ids):
    if not ids: return [], []
    desc = ec2.describe_instances(InstanceIds=ids)
    spot, ond = [], []
    for r in desc.get("Reservations", []):
        for i in r.get("Instances", []):
            if i.get("InstanceLifecycle") == "spot":
                spot.append(i["InstanceId"])
            else:
                ond.append(i["InstanceId"])
    return unique(ond), unique(spot)

# ----------------- RDS helpers -----------------
def rds_instance_status(dbid):
    try:
        db = rds.describe_db_instances(DBInstanceIdentifier=dbid)["DBInstances"][0]
        return db.get("DBInstanceStatus", "")
    except Exception:
        return ""

def wait_rds_available(dbid, timeout_s):
    if timeout_s <= 0: return False
    waiter = rds.get_waiter("db_instance_available")
    try:
        waiter.wait(DBInstanceIdentifier=dbid, WaiterConfig={"Delay": 15, "MaxAttempts": max(1, timeout_s // 15)})
        return True
    except Exception:
        return False

# ----------------- Actions: EC2/ASG/ECS/RDS -----------------
def handle_ec2(action, ec2_ids):
    res = {"ec2": {"requested": ec2_ids, "ok": [], "terminated": [], "skipped": [], "errors": []}}
    if not ec2_ids: return res
    terminate_spot_on_off = os.getenv("EC2_TERMINATE_SPOT_ON_OFF", "false").lower() in ("1","true","yes","y","si","sí")
    try:
        ond, spot = split_spot_and_ondemand(ec2_ids)
        if ond:
            for i in range(0, len(ond), 100):
                chunk = ond[i:i+100]
                if action == "on": ec2.start_instances(InstanceIds=chunk)
                else:             ec2.stop_instances(InstanceIds=chunk)
            res["ec2"]["ok"] += ond
        if spot:
            if action == "off" and terminate_spot_on_off:
                for i in range(0, len(spot), 100):
                    ec2.terminate_instances(InstanceIds=spot[i:i+100])
                res["ec2"]["terminated"] += spot
            else:
                res["ec2"]["skipped"] += spot
    except Exception as e:
        logger.exception("EC2 error")
        res["ec2"]["errors"].append(str(e))
    return res

def handle_asg(action, asg_names, asg_tags, default_desired):
    """
    - asg_names: str "asg1,asg2" o vacío
    - asg_tags: dict o {}
    - default_desired: int o None
    """
    result = {"asg": {"matched": [], "updated": [], "errors": [], "skipped": [], "terminated_instances": []}}

    # Descubrimiento
    if asg_names:
        groups = get_asgs_by_names(asg_names)
    elif asg_tags:
        groups = get_asgs_by_tags(asg_tags)
    else:
        groups = list_asgs()  # cuidado: todos los ASG

    result["asg"]["matched"] = [g["AutoScalingGroupName"] for g in groups]
    force_term = os.getenv("ASG_FORCE_TERMINATE", "true").lower() in ("1","true","yes","y","si","sí")
    force_hook = os.getenv("ASG_FORCE_COMPLETE_HOOK", "true").lower() in ("1","true","yes","y","si","sí")
    ecs_cluster_for_drain = os.getenv("ECS_CLUSTER_NAME", "")  # opcional

    for g in groups:
        name   = g["AutoScalingGroupName"]
        desired = g.get("DesiredCapacity", 0)
        minsize = g.get("MinSize", 0)
        maxsize = g.get("MaxSize", 0)
        try:
            if action == "off":
                # guardar estado previo y bajar a 0 (incluye max=0)
                tag_asg(name, TAG_PREV_DESIRED, desired)
                tag_asg(name, TAG_PREV_MIN, minsize)
                asg.update_auto_scaling_group(
                    AutoScalingGroupName=name,
                    MinSize=0,
                    DesiredCapacity=0,
                    MaxSize=0
                )
                result["asg"]["updated"].append({name: {"prev_desired": desired, "prev_min": minsize, "prev_max": maxsize, "new": {"min":0,"desired":0,"max":0}}})

                # manejar instancias remanentes
                instance_ids = asg_instance_ids(g)
                for iid in instance_ids:
                    # opcional: drenar/deregistrar en ECS
                    if ecs_cluster_for_drain:
                        try:
                            ci_arn = container_instance_arn_for_ec2(ecs_cluster_for_drain, iid)
                            if ci_arn:
                                drain_and_deregister_container_instance(ecs_cluster_for_drain, ci_arn)
                        except Exception as e:
                            logger.info("Drain/Deregister fail %s: %s", iid, str(e))

                    # completar lifecycle hooks si existen
                    if force_hook:
                        hooks = list_lifecycle_hooks(name)
                        for h in hooks:
                            if h.get("LifecycleTransition") == "autoscaling:EC2_INSTANCE_TERMINATING":
                                try:
                                    complete_lifecycle_continue(name, h["LifecycleHookName"], iid)
                                    logger.info("Completed lifecycle hook %s for %s", h["LifecycleHookName"], iid)
                                except Exception as e:
                                    logger.info("CompleteLifecycleAction failed for %s: %s", iid, str(e))

                    # quitar protección y terminar instancia
                    if force_term:
                        try:
                            disable_instance_protection(name, [iid])
                        except Exception as e:
                            logger.info("Disable protection failed for %s: %s", iid, str(e))
                        try:
                            ec2.terminate_instances(InstanceIds=[iid])
                            result["asg"]["terminated_instances"].append(iid)
                        except Exception as e:
                            logger.info("Terminate %s failed: %s", iid, str(e))

            else:
                # restaurar desde tags
                #prev_desired = get_tag(g, TAG_PREV_DESIRED)
                #prev_min     = get_tag(g, TAG_PREV_MIN)
                prev_desired = 1
                prev_min     = 1
                if prev_desired is None and default_desired is not None:
                    prev_desired = default_desired
                if prev_min is None:
                    prev_min = 1
                #prev_desired = int(prev_desired) if prev_desired is not None else 0
                #prev_min     = int(prev_min) if prev_min is not None else 0
                prev_desired = 1
                prev_min     = 1

                if prev_desired == 0 and default_desired is None and get_tag(g, TAG_PREV_DESIRED) is None:
                    result["asg"]["skipped"].append({name: "sin estado previo ni ASG_DEFAULT_DESIRED"})
                    continue

                new_max = max(prev_desired, 1)
                asg.update_auto_scaling_group(
                    AutoScalingGroupName=name,
                    MinSize=prev_min,
                    DesiredCapacity=prev_desired,
                    MaxSize=new_max
                )
                result["asg"]["updated"].append({name: {"restored_desired": prev_desired, "restored_min": prev_min, "restored_max": new_max}})
        except Exception as e:
            logger.exception("ASG error for %s", name)
            result["asg"]["errors"].append({name: str(e)})

    return result

def handle_ecs_services(action, cluster_names, cluster_tags, svc_prefix, default_desired, tune_autoscaling):
    result = {"ecs": {"clusters": [], "services_scaled": [], "skipped": [], "errors": []}}
    # Descubrimiento de clusters
    if cluster_names:
        clusters = clusters_by_names(cluster_names)
    elif cluster_tags:
        clusters = clusters_by_tags(cluster_tags)
    else:
        clusters = list_ecs_clusters()  # cuidado: todos
    result["ecs"]["clusters"] = clusters

    for c_arn in clusters:
        svcs = filter_services_by_prefix(c_arn, svc_prefix)
        if not svcs: continue
        for i in range(0, len(svcs), 10):
            chunk = svcs[i:i+10]
            desc = ecs.describe_services(cluster=c_arn, services=chunk)
            for s in desc.get("services", []):
                svc_arn = s["serviceArn"]
                svc_name = s["serviceName"]
                current_desired = s.get("desiredCount", 0)
                try:
                    tags = get_service_tags(svc_arn)
                    if action == "off":
                        put_service_tag(svc_arn, TAG_SVC_PREV_DESIRED, current_desired)
                        update_service_desired(c_arn, svc_arn, 0)
                        if tune_autoscaling:
                            tune_app_autoscaling(c_arn, svc_arn, 0, 0)
                        result["ecs"]["services_scaled"].append({svc_name: {"prev_desired": current_desired, "new_desired": 0}})
                    else:
                        prev = tags.get(TAG_SVC_PREV_DESIRED)
                        if prev is None and default_desired is None:
                            result["ecs"]["skipped"].append({svc_name: "sin estado previo ni ECS_DEFAULT_DESIRED"})
                            continue
                        #desired = int(prev) if prev is not None else int(default_desired)
                        desired = 1
                        update_service_desired(c_arn, svc_arn, desired)
                        if tune_autoscaling:
                            tune_app_autoscaling(c_arn, svc_arn, 1, max(desired, 1))
                        result["ecs"]["services_scaled"].append({svc_name: {"restored_desired": desired}})
                except Exception as e:
                    logger.exception("ECS service error for %s", svc_name)
                    result["ecs"]["errors"].append({svc_name: str(e)})
    return result

def handle_rds(action, rds_inst_ids, rds_cluster_ids):
    res = {
        "rds_instances": {"requested": rds_inst_ids, "ok": [], "unsupported": [], "skipped": [], "errors": []},
        "rds_clusters":  {"requested": rds_cluster_ids, "ok": [], "unsupported": [], "skipped": [], "errors": []},
    }
    try:
        wait_secs = int(os.getenv("RDS_WAIT_AVAILABLE_SECONDS", "0"))
    except ValueError:
        wait_secs = 0

    for dbid in rds_inst_ids:
        try:
            status = rds_instance_status(dbid)
            if action == "off":
                if status == "available":
                    rds.stop_db_instance(DBInstanceIdentifier=dbid)
                    res["rds_instances"]["ok"].append(dbid)
                elif status in ("stopped", "stopping"):
                    res["rds_instances"]["skipped"].append({dbid: status})
                else:
                    if wait_secs > 0 and wait_rds_available(dbid, wait_secs):
                        rds.stop_db_instance(DBInstanceIdentifier=dbid)
                        res["rds_instances"]["ok"].append(dbid)
                    else:
                        res["rds_instances"]["errors"].append({dbid: f"state={status}; no se pudo detener"})
            else:
                if status == "stopped":
                    rds.start_db_instance(DBInstanceIdentifier=dbid)
                    res["rds_instances"]["ok"].append(dbid)
                elif status in ("available", "starting"):
                    res["rds_instances"]["skipped"].append({dbid: status})
                else:
                    res["rds_instances"]["errors"].append({dbid: f"state={status}; no se pudo iniciar"})
        except Exception as e:
            msg = str(e)
            logger.exception("RDS Instance error for %s", dbid)
            if "cannot be stopped" in msg.lower() or "not supported" in msg.lower():
                res["rds_instances"]["unsupported"].append({dbid: msg})
            else:
                res["rds_instances"]["errors"].append({dbid: msg})

    for clid in rds_cluster_ids:
        try:
            if action == "on": rds.start_db_cluster(DBClusterIdentifier=clid)
            else:             rds.stop_db_cluster(DBClusterIdentifier=clid)
            res["rds_clusters"]["ok"].append(clid)
        except Exception as e:
            msg = str(e)
            logger.exception("RDS Cluster error for %s", clid)
            if "cannot be stopped" in msg.lower() or "not supported" in msg.lower():
                res["rds_clusters"]["unsupported"].append({clid: msg})
            else:
                res["rds_clusters"]["errors"].append({clid: msg})
    return res

# ----------------- Handler -----------------
def build_response(code, body):
    return {
        "statusCode": code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
        "isBase64Encoded": False,
    }

def handler(event, context):
    logger.info("Event: %s", json.dumps(event))
    path = (event.get("path") or "").lower()
    action = "on" if path.endswith("/on") else "off" if path.endswith("/off") else None
    if not action:
        return build_response(400, {"error": "Ruta inválida. Use POST /on o /off"})

    # Config
    ec2_ids_env        = os.getenv("EC2_INSTANCE_IDS", "")
    rds_ids_env        = os.getenv("RDS_INSTANCE_IDS", "")
    target_tags_env    = os.getenv("TARGET_TAGS_JSON", "{}")

    # ASG
    asg_names_env      = os.getenv("ASG_NAMES", "")
    asg_tags_env       = os.getenv("ASG_TAGS_JSON", "{}")
    asg_default_str    = os.getenv("ASG_DEFAULT_DESIRED", "1")

    # ECS
    ecs_cluster_names  = os.getenv("ECS_CLUSTER_NAMES", "")
    ecs_cluster_tags   = os.getenv("ECS_CLUSTER_TAGS", "{}")
    svc_prefix         = os.getenv("ECS_SVC_PREFIX", "")
    ecs_default_str    = os.getenv("ECS_DEFAULT_DESIRED", "1")
    tune_as_str        = os.getenv("ECS_TUNE_AUTOSCALING", "false")

    # Parse JSON/enteros
    try:    target_tags = json.loads(target_tags_env) if target_tags_env else {}
    except json.JSONDecodeError: target_tags = {}
    try:    asg_tags = json.loads(asg_tags_env) if asg_tags_env else {}
    except json.JSONDecodeError: asg_tags = {}
    try:    ecs_tags = json.loads(ecs_cluster_tags) if ecs_cluster_tags else {}
    except json.JSONDecodeError: ecs_tags = {}

    try:    asg_default_desired = int(asg_default_str) if asg_default_str else None
    except ValueError: asg_default_desired = None
    try:    ecs_default_desired = int(ecs_default_str) if ecs_default_str else None
    except ValueError: ecs_default_desired = None

    tune_autoscaling = tune_as_str.lower() in ("1","true","yes","y","si","sí")

    ec2_ids         = [i.strip() for i in ec2_ids_env.split(",") if i.strip()]
    rds_inst_ids    = [i.strip() for i in rds_ids_env.split(",") if i.strip()]
    rds_cluster_ids = []

    # Descubrimiento por tags
    if target_tags:
        ec2_ids = unique(ec2_ids + get_ec2_by_tags(target_tags))
        inst_by_tag, clus_by_tag = get_rds_by_tags(target_tags)
        rds_inst_ids    = unique(rds_inst_ids + inst_by_tag)
        rds_cluster_ids = unique(rds_cluster_ids + clus_by_tag)

    # Si no se pasó nada, tomar TODO en la región
    if not ec2_ids and not target_tags:
        ec2_ids = get_all_ec2_ids()
    if not rds_inst_ids and not rds_cluster_ids and not target_tags:
        rds_inst_ids    = get_all_rds_instances()
        rds_cluster_ids = get_all_rds_clusters()

    result = {
        "action": action,
        "targets": {
            "ecs": {"cluster_names": ecs_cluster_names, "cluster_tags": ecs_tags, "service_prefix": svc_prefix},
            "asg": {"names": asg_names_env, "tags": asg_tags},
            "ec2": ec2_ids,
            "rds_instances": rds_inst_ids,
            "rds_clusters": rds_cluster_ids
        }
    }

    # 1) ECS services (apaga/prende tasks)
    result.update(handle_ecs_services(action, ecs_cluster_names, ecs_tags, svc_prefix, ecs_default_desired, tune_autoscaling))

    # 2) ASG (capacidad)
    result.update(handle_asg(action, asg_names_env, asg_tags, asg_default_desired))

    # 3) EC2/RDS
    result.update(handle_ec2(action, ec2_ids))
    result.update(handle_rds(action, rds_inst_ids, rds_cluster_ids))

    return build_response(200, result)

  PY
}


data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src"
  output_path = "${path.module}/lambda_src.zip"
}

# ---------- IAM Role para Lambda ----------
data "aws_iam_policy_document" "assume_lambda" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  description        = "Permite a Lambda operar EC2/RDS y escribir logs"
}

# Logs
resource "aws_iam_role_policy_attachment" "lambda_logs_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permisos mínimos EC2/RDS (incluye clusters)
data "aws_iam_policy_document" "lambda_control" {
  statement {
    sid     = "EC2Control"
    effect  = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:SetDesiredCapacity",
      "ec2:TerminateInstances",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:CreateOrUpdateTags",
      "application-autoscaling:DescribeScalableTargets",
      "application-autoscaling:RegisterScalableTarget",
      "ecs:ListClusters",
      "ecs:DescribeClusters",
      "ecs:ListServices",
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "ecs:ListTagsForResource",
      "ecs:TagResource",
      "ecs:UntagResource",
      "autoscaling:SetInstanceProtection",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLifecycleHooks",
      "autoscaling:CompleteLifecycleAction",

    ]
    resources = ["*"]
  }

  statement {
    sid     = "RDSControl"
    effect  = "Allow"
    actions = [
      "rds:DescribeDBInstances",
      "rds:DescribeDBClusters",
      "rds:ListTagsForResource",
      "rds:StartDBInstance",
      "rds:StopDBInstance",
      "rds:StartDBCluster",
      "rds:StopDBCluster"
    ]
    resources = ["*"]
  }


}

resource "aws_iam_policy" "lambda_control" {
  name   = "${var.name}-lambda-control"
  policy = data.aws_iam_policy_document.lambda_control.json
}

resource "aws_iam_role_policy_attachment" "lambda_control_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_control.arn
}

# ---------- Lambda ----------
resource "aws_cloudwatch_log_group" "lambda_lg" {
  name              = "/aws/lambda/${var.name}-switcher"
  retention_in_days = 1
}

resource "aws_lambda_function" "switcher" {
  function_name = "${var.name}-switcher"
  role          = aws_iam_role.lambda_role.arn
  handler       = "main.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lambda_zip.output_path
  timeout       = 60
  memory_size   = 256

  environment {
    variables = {
      EC2_INSTANCE_IDS = join(",", var.ec2_instance_ids)   # opcional
      RDS_INSTANCE_IDS = join(",", var.rds_instance_ids)   # opcional
      TARGET_TAGS_JSON = jsonencode(var.target_tags)       # opcional
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_lg]
}


