# infra-stock-ahora
Repositorio que contiene los artefactos para levantar la infra estructura de aws 


## Levantar infra

para poder levantar la infra es necesario estar ubicado en el directorio **infra/modules**, una vez en esta ubicación lo ideal es lanzar los modulos separadamente
esto quiere decir que para ejecutar los modules de vpc por ejemplo es necesario el siguiente comando 

```bash
 terraform plan -target="module.vpc"
````

## autorización

Esta infraestructura tiene un backend que utiliza dynamoDB para bloquera acciones cuando se estan realizando ademas de un S3 que es donde se almacenan los cambios relacionados con la infra. 

Esto es principalmente para que se pueda ejecutar desde cualquier computador
lo que si es necesario iniciar secion con el usuario que tiene los permisos para levantar servicios de aws 
es necesario agregarlo de esta manera para que te permita utilizar sus credenciales (previamente tienes que haber iniciado secion con las credenciales con el cliente de aws v2).

```bash
$aws_profile = "terraform-user"
```


## Orden de ejecucion

en nuestra infra es deseado ejecutar los modulos en el siguiente orden

1. vpc
2. s3-static-site
3. cloudfront-static-site
4. ecs
5. api-client-api

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
    - URL: https://d1m7sx3h5fgsnc.cloudfront.net


