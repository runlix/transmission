# Transmission Distroless

Kubernetes-native distroless Docker image for [Transmission](https://github.com/transmission/transmission).

## Features

- Distroless base (no shell, minimal attack surface)
- Kubernetes-native permissions (no s6-overlay)
- Read-only root filesystem
- Non-root execution
- Minimal image size (~100MB vs ~500MB)

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
  ghcr.io/runlix/transmission-distroless:release
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
        image: ghcr.io/runlix/transmission-distroless:release
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

## Tags

See [tags.json](tags.json) for available tags.

## Ports

- **9091**: Web UI (HTTP)
- **51413**: Peer port (TCP and UDP)

## License

GPL-2.0
