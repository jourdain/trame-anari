# ANARI Pan3D demo

## Build docker image

```
docker build --progress=plain -t pan3d-anari .
```

## Run trame application

```
docker run --gpus all -p 12345:80 -it pan3d-anari 
```

## Debug cmds

```
docker run --gpus all --entrypoint /bin/bash -it pan3d-anari 
```