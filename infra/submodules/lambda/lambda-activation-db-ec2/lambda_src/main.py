import os, json, logging, boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
rds = boto3.client("rds")
asg = boto3.client("autoscaling")

TAG_PREV_DESIRED = "PowerSwitchPrevDesired"
TAG_PREV_MIN     = "PowerSwitchPrevMin"

def unique(seq):
    return list(dict.fromkeys(seq))

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
    if not tags:
        return []
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
    if not tags:
        return [], []
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
    if not ids:
        return [], []
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
    if timeout_s <= 0:
        return False
    waiter = rds.get_waiter("db_instance_available")
    try:
        waiter.wait(DBInstanceIdentifier=dbid, WaiterConfig={"Delay": 15, "MaxAttempts": max(1, timeout_s // 15)})
        return True
    except Exception:
        return False

# ----------------- ASG helpers -----------------
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

# ----------------- Actions: EC2/ASG/RDS -----------------
def handle_ec2(action, ec2_ids):
    res = {"ec2": {"requested": ec2_ids, "ok": [], "terminated": [], "skipped": [], "errors": []}}
    if not ec2_ids:
        return res

    terminate_spot_on_off = os.getenv("EC2_TERMINATE_SPOT_ON_OFF", "false").lower() in ("1","true","yes","y","si","sí")

    try:
        ond, spot = split_spot_and_ondemand(ec2_ids)

        # On-Demand → start/stop
        if ond:
            for i in range(0, len(ond), 100):
                chunk = ond[i:i+100]
                if action == "on":
                    ec2.start_instances(InstanceIds=chunk)
                else:
                    ec2.stop_instances(InstanceIds=chunk)
            res["ec2"]["ok"] += ond

        # Spot → terminate en OFF (si flag activado), skip en ON
        if spot:
            if action == "off" and terminate_spot_on_off:
                for i in range(0, len(spot), 100):
                    chunk = spot[i:i+100]
                    ec2.terminate_instances(InstanceIds=chunk)
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
    result = {"asg": {"matched": [], "updated": [], "errors": [], "skipped": []}}

    # Descubrimiento
    groups = []
    if asg_names:
        groups = get_asgs_by_names(asg_names)
    elif asg_tags:
        groups = get_asgs_by_tags(asg_tags)
    else:
        # Si no especificas nada, actuamos sobre TODOS los ASG (cuidado)
        groups = list_asgs()

    result["asg"]["matched"] = [g["AutoScalingGroupName"] for g in groups]

    for g in groups:
        name = g["AutoScalingGroupName"]
        desired = g.get("DesiredCapacity", 0)
        minsize = g.get("MinSize", 0)

        try:
            if action == "off":
                # guardar estado previo en tags
                tag_asg(name, TAG_PREV_DESIRED, desired)
                tag_asg(name, TAG_PREV_MIN, minsize)
                # bajar a 0
                asg.update_auto_scaling_group(AutoScalingGroupName=name, MinSize=0, DesiredCapacity=0)
                result["asg"]["updated"].append({name: {"prev_desired": desired, "prev_min": minsize, "new_desired": 0, "new_min": 0}})
            else:
                # restaurar desde tags
                prev_desired = get_tag(g, TAG_PREV_DESIRED)
                prev_min     = get_tag(g, TAG_PREV_MIN)
                if prev_desired is None and default_desired is not None:
                    prev_desired = default_desired
                if prev_min is None:
                    prev_min = 0
                # saneo tipos
                prev_desired = int(prev_desired) if prev_desired is not None else 0
                prev_min     = int(prev_min) if prev_min is not None else 0

                # si no hay info previa y tampoco default, evita rebotar a >0 sin control
                if prev_desired == 0 and default_desired is None and get_tag(g, TAG_PREV_DESIRED) is None:
                    result["asg"]["skipped"].append({name: "sin estado previo ni ASG_DEFAULT_DESIRED"})
                    continue

                asg.update_auto_scaling_group(AutoScalingGroupName=name, MinSize=prev_min, DesiredCapacity=prev_desired)
                result["asg"]["updated"].append({name: {"restored_desired": prev_desired, "restored_min": prev_min}})
        except Exception as e:
            logger.exception("ASG error for %s", name)
            result["asg"]["errors"].append({name: str(e)})

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

    # Instancias
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
            else:  # ON
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

    # Clusters (Aurora)
    for clid in rds_cluster_ids:
        try:
            if action == "on":
                rds.start_db_cluster(DBClusterIdentifier=clid)
            else:
                rds.stop_db_cluster(DBClusterIdentifier=clid)
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
    asg_names_env      = os.getenv("ASG_NAMES", "")                # "asg1,asg2"
    asg_tags_env       = os.getenv("ASG_TAGS_JSON", "{}")          # {"Project":"stock-ahora"}
    asg_default_str    = os.getenv("ASG_DEFAULT_DESIRED", "")

    try:
        target_tags = json.loads(target_tags_env) if target_tags_env else {}
    except json.JSONDecodeError:
        target_tags = {}
    try:
        asg_tags = json.loads(asg_tags_env) if asg_tags_env else {}
    except json.JSONDecodeError:
        asg_tags = {}
    try:
        asg_default_desired = int(asg_default_str) if asg_default_str else None
    except ValueError:
        asg_default_desired = None

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
            "asg": {"names": asg_names_env, "tags": asg_tags},
            "ec2": ec2_ids,
            "rds_instances": rds_inst_ids,
            "rds_clusters": rds_cluster_ids
        }
    }

    # Primero ASG (para que ECS no recree)
    result.update(handle_asg(action, asg_names_env, asg_tags, asg_default_desired))
    # Luego EC2/RDS a modo complementario
    result.update(handle_ec2(action, ec2_ids))
    result.update(handle_rds(action, rds_inst_ids, rds_cluster_ids))

    return build_response(200, result)
