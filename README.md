# Transmission

Kubernetes-native distroless Docker image for [Transmission](https://github.com/transmission/transmission), built and published through the shared CI v3 workflow stack in [`runlix/build-workflow`](https://github.com/runlix/build-workflow).

## Published Image

- Image: `ghcr.io/runlix/transmission`
- Current stable tag example: `ghcr.io/runlix/transmission:4.1.1-stable`
- Current debug tag example: `ghcr.io/runlix/transmission:4.1.1-debug`

The authoritative published tags, digests, and source revision are recorded in [release.json](release.json).

## Branch Layout

- `main`: documentation, release metadata, and automation configuration
- `release`: Dockerfiles, CI wrappers, smoke tests, and build inputs

Normal release flow:
1. changes land on `release`
2. `Publish Release` builds and publishes the images
3. the workflow opens a sync PR back to `main`
4. `main` records the published result in `release.json`

## Usage

### Docker

```bash
docker run -d \
  --name transmission \
  -p 9091:9091 \
  -p 51413:51413 \
  -p 51413:51413/udp \
  -v /path/to/config:/config \
  -v /path/to/downloads:/downloads \
  ghcr.io/runlix/transmission:4.1.1-stable
```

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: transmission
spec:
  template:
    spec:
      containers:
        - name: transmission
          image: ghcr.io/runlix/transmission:4.1.1-stable
          ports:
            - containerPort: 9091
              name: webui
            - containerPort: 51413
              name: peer-tcp
            - containerPort: 51413
              protocol: UDP
              name: peer-udp
          volumeMounts:
            - name: config
              mountPath: /config
            - name: downloads
              mountPath: /downloads
          securityContext:
            runAsUser: 65532
            runAsGroup: 65532
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: transmission-config
        - name: downloads
          persistentVolumeClaim:
            claimName: transmission-downloads
      securityContext:
        fsGroup: 65532
```

## Ports

- `9091`: Web UI
- `51413/tcp`: peer traffic
- `51413/udp`: peer traffic

## License

GPL-2.0
