# ANARI Pan3D demo

## Build docker image

```
docker build --progress=plain -t pan3d-anari .
```

## Run trame application

```
# ANARI_LIBRARY can be "helide", "visgl", "visrtx"
docker run --gpus all -e ANARI_LIBRARY=helide -p 12345:80 -it pan3d-anari 
```

## Debug cmds

```
docker run --gpus all --entrypoint /bin/bash -it pan3d-anari 
```