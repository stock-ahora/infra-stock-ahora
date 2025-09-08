y# infra-stock-ahora
Repositorio que contiene los artefactos para levantar la infra estructura de aws 


## Levantar infra

Para poder levantar la infra es necesario estar ubicado en el directorio **infra/modules**, una vez en esta ubicación lo ideal es lanzar los modulos separadamente
esto quiere decir que para ejecutar los modules de vpc por ejemplo es necesario el siguiente comando 

```bash
 terraform plan -target="module.vpc"
````

## autorización

Esta infraestructura tiene un backend que utiliza dynamoDB para bloquear acciones cuando se estan realizando ademas de un S3 que es donde se almacenan los cambios relacionados con la infra. 

Esto es principalmente para que se pueda ejecutar desde cualquier computador
lo que si es necesario iniciar sesión con el usuario que tiene los permisos para levantar servicios de aws 
es necesario agregarlo de esta manera para que te permita utilizar sus credenciales (previamente tienes que haber iniciado secion con las credenciales con el cliente de aws v2).

```bash
$aws_profile = "terraform-user"
```

### scipt para subir servicios

```bash
terraform init

```

## Ordenes de los archivos

Los archivos se encuentran ordenadas de tal forma que modules se refuere a los servicios de aws, mientras que submodulos son las configuraciones de cada servicio en particular,
esto quiere decir que por ejemplo tenermos s3.tf donde estaran todos los s3 que se levanten, pero las configuraciones en especifico se encuentra en submodules,
done estan los resourse, considerar que los modulos tienen el path donde esta la configuracion de ese modulo.


## Servicios actuales

1. cloud-front
    - URL: https://d11g8rxsz1yv0r.cloudfront.net/


## envs para qe corra el terraform

```bash

$env:AWS_PROFILE="terraform-user-2

$env:AWS_REGION="us-east-2"

```


## Arbol de dependencias

Este árbol muestra el orden de ejecución de los servicios de aws para su correcta implementación en nuesto único ambiente. 

<img src="arbol%20de%20dependencias%20terraform.drawio.png" alt="Logo" width="600"/>


Primeros módulos:

- s3 docs
- vpc
- s3-static-site
- ecr

Segundos módulos:

-task app
-cloudfront-static-site
-aim-ecr


Terceros módulos:

- secret-app
- ecs
- db-main
- ec2-rabbitMQ

Cuarto Modulo:

- api-cliente


## Ramas

Este proyecto esta configurado de tal forma que cuando corres el pipeline en la rama de **main** es para levantar la infra o actualizarla en el caso de que ya se encuentre levantada
por otro lado tenemos los la rama **destroy** la cual corre el pipeline que elimina toda la infra estructura.