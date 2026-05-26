# Nominatim for Kubernetes
[![](https://images.microbadger.com/badges/image/peterevans/nominatim-k8s.svg)](https://microbadger.com/images/peterevans/nominatim-k8s)
[![CircleCI](https://circleci.com/gh/peter-evans/nominatim-k8s/tree/master.svg?style=svg)](https://circleci.com/gh/peter-evans/nominatim-k8s/tree/master)

[Nominatim](https://github.com/openstreetmap/Nominatim) for Kubernetes.

This Docker image and sample Kubernetes configuration files are one solution to persisting Nominatim data and providing immutable deployments using S3-compatible storage (like AWS S3 or ArvanCloud).

## Supported tags and respective `Dockerfile` links

- [`2.6.2`, `2.6`, `latest`, `2.6.2-nominatim3.5.2`, `2.6-nominatim3.5.2`, `latest-nominatim3.5.2`  (*2.6/Dockerfile*)](https://github.com/peter-evans/nominatim-docker/tree/v2.6.2)
- [`2.6.1`, `2.6.1-nominatim3.5.1`, `2.6-nominatim3.5.1`, `latest-nominatim3.5.1`  (*2.6/Dockerfile*)](https://github.com/peter-evans/nominatim-docker/tree/v2.6.1)
- [`2.6.0`, `2.6.0-nominatim3.5.0`, `2.6-nominatim3.5.0`, `latest-nominatim3.5.0`  (*2.6/Dockerfile*)](https://github.com/peter-evans/nominatim-docker/tree/v2.6.0)
- [`2.5.4`, `2.5`, `2.5.4-nominatim3.4.2`, `2.5-nominatim3.4.2`, `latest-nominatim3.4.2`  (*2.5/Dockerfile*)](https://github.com/peter-evans/nominatim-docker/tree/v2.5.4)

## Usage
The Docker image can be run standalone without Kubernetes:

```bash
docker run -d -p 8080:8080 \
-e NOMINATIM_PBF_URL='http://download.geofabrik.de/asia/maldives-latest.osm.pbf' \
--name nominatim peterevans/nominatim-k8s:latest
```
Tail the logs to verify the database has been built and Apache is serving requests:
```
docker logs -f <CONTAINER ID>
```
Then point your web browser to [http://localhost:8080/](http://localhost:8080/)

## Kubernetes Deployment
[Nominatim](https://github.com/openstreetmap/Nominatim)'s data import from the PBF file into PostgreSQL can take over an hour for a single country.
If a pod in a deployment fails, waiting over an hour for a new pod to start could lead to loss of service.

The sample Kubernetes files provide a means of persisting a single database in storage that is used by all pods in the deployment. 
Each pod having its own database is desirable in order to have no single point of failure. 
The alternative to this solution is to maintain a HA PostgreSQL cluster.

PostgreSQL's data directory is archived in storage and restored on new pods. 
While this may be a crude method of copying the database it is much faster than pg_dump/pg_restore and reduces the pod startup time.

#### Explanation
Initial deployment flow:

1. Create access keys for your S3-compatible object storage (e.g., AWS IAM or ArvanCloud Storage).
2. Deploy the canary deployment.
3. Wait for the database to be created and its archive uploaded to S3 storage.
4. Delete the canary deployment.
5. Deploy the stable track deployment.

To update the live deployment with new PBF data:

1. Deploy the canary deployment alongside the stable track deployment.
2. Wait for the database to be created and its archive uploaded to S3 storage.
3. Delete the canary deployment.
4. Perform a rolling update on the stable track deployment to create pods using the new database.

#### Creating the secret

```bash
# Set your S3 credentials (for AWS, ArvanCloud, or other S3-compatible endpoints)
ACCESS_KEY_ID=my-access-key
SECRET_ACCESS_KEY=my-secret-key

# Create a secret containing the S3 credentials
kubectl create secret generic nominatim-storage-secret \
  --from-literal=access-key-id=$ACCESS_KEY_ID \
  --from-literal=secret-access-key=$SECRET_ACCESS_KEY
```  

#### Deployment configuration
Before deploying, edit the `env` section of both the canary deployment and stable track deployment.

- `NOMINATIM_MODE` - `CREATE` from PBF data, or `RESTORE` from S3.
- `NOMINATIM_PBF_URL` - URL to PBF data file. (Optional when `NOMINATIM_MODE=RESTORE`)
- `NOMINATIM_DATA_LABEL` - A meaningful and **unique** label for the data. e.g. maldives-20161213
- `NOMINATIM_AWS_ACCESS_KEY_ID` - S3 Access Key ID.
- `NOMINATIM_AWS_SECRET_ACCESS_KEY` - S3 Secret Access Key.
- `NOMINATIM_AWS_REGION` - S3 region (e.g., `ir-thr-at1` for ArvanCloud or `us-east-1` for AWS).
- `NOMINATIM_S3_BUCKET` - S3 bucket name.
- `NOMINATIM_PG_THREADS` - Number of threads available for PostgreSQL. Defaults to 2.

#### Image Registry Configuration
By default, the Kubernetes deployment files are configured to pull the image from the GitHub Container Registry (`ghcr.io/YOUR_GITHUB_USERNAME/nominatim-k8s:latest`). Before deploying, make sure to edit the `image` field and replace `YOUR_GITHUB_USERNAME` with your actual account or organization name.

If you are using a **Private Registry** (e.g., ArvanCloud Container Registry, private Docker Hub):
1. Create a Docker registry secret in your Kubernetes cluster:
   ```bash
   kubectl create secret docker-registry private-registry-auth \
     --docker-server=docker.arvancloud.ir \
     --docker-username=YOUR_USERNAME \
     --docker-password=YOUR_PASSWORD
   ```
2. Update the `image` field in both `nominatim-canary.yaml` and `nominatim.yaml` to point to your private image URL.
3. Uncomment the `imagePullSecrets` block in the `spec` section of both YAML files so Kubernetes can authenticate to pull the image.

## CI/CD Pipeline (GitHub Actions)

This repository includes a GitHub Actions workflow that automatically builds and publishes the Docker image across multiple registries when changes are pushed to the `master` branch or when a new version tag (e.g., `v1.0.0`) is pushed.

### Supported Registries

1. **GitHub Container Registry (ghcr.io)**
   Authentication and publishing to GHCR are handled automatically using the internal `GITHUB_TOKEN`. No additional secrets setup is required.

2. **Docker Hub (Optional)**
   To publish the image to Docker Hub, configure the following **Repository Secrets** in your GitHub repository (`Settings` > `Secrets and variables` > `Actions`):
   - `DOCKERHUB_USERNAME`: Your Docker Hub username.
   - `DOCKERHUB_PASSWORD`: Your Docker Hub password or access token.
   - `DOCKERHUB_REPOSITORY` (Optional): The explicit image repository name (e.g., `my-org/nominatim-k8s`). If not provided, it defaults to `<username>/<github-repo-name>`.

3. **Private Registries (Optional)**
   To publish to a custom or private Docker registry (e.g., ArvanCloud Container Registry), configure these **Repository Secrets**:
   - `PRIVATE_REGISTRY_URL`: The registry URL endpoint (e.g., `docker.arvancloud.ir`).
   - `PRIVATE_REGISTRY_USERNAME`: Your registry username.
   - `PRIVATE_REGISTRY_PASSWORD`: Your registry password.
   - `PRIVATE_REGISTRY_REPOSITORY` (Optional): The explicit repository path (e.g., `docker.arvancloud.ir/myworkspace/nominatim`). If not provided, it defaults to `<registry-url>/<username>/<github-repo-name>`.

## License

MIT License - see the [LICENSE](LICENSE) file for details
