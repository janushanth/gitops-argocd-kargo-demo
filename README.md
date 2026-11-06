# gitops-argocd-kargo-demo

Local Docker Desktop demo.

GitHub Actions builds the Hello World image, tags it `1.0.<run>`, and pushes it to Sonatype Nexus. Kargo sees that tag and promotes it. Argo CD deploys it. Argo CD also installs Kargo.

```text
hello-world/Dockerfile
  -> GitHub Actions
  -> Nexus  nexus.example.com:8082/hello-world:1.0.N
  -> Kargo Warehouse
  -> promote test (automatic) -> gitops/test
  -> promote prod (manual)    -> gitops/prod
  -> Argo CD rolls the pods
```

Replace `nexus.example.com:8082` in this repo with your Nexus Docker host and port before the first install. Use that same host:port as the GitHub secret `NEXUS_REGISTRY`. The image name is `hello-world`.

| Environment | Manifest | Starts at | Promotion |
|---|---|---|---|
| test | `gitops/test/deployment.yaml` | `0.0.0` | Automatic for tags `1.0.N` |
| prod | `gitops/prod/deployment.yaml` | `0.0.0` | Manual in the Kargo UI, after test |

## What is in this repo

| Path | Purpose |
|---|---|
| `hello-world/Dockerfile` | Hello World page. The image tag is baked into the page |
| `.github/workflows/build-publish.yml` | Builds and pushes `1.0.<run>` to Nexus. Ignores Kargo commits under `gitops/` |
| `install/install.ps1` | Installs cert-manager and Argo CD. Argo CD installs Kargo |
| `install/kargo/values.yaml` | Helm values Argo CD uses for Kargo |
| `install/cleanup.ps1` | Removes the demo and puts the image tag back to `0.0.0` |
| `argocd/kargo-application.yaml` | Argo CD Application for the Kargo Helm chart |
| `argocd/kargo-config-application.yaml` | Argo CD Application for the Kargo Project, Warehouse, and Stages |
| `argocd/hello-world-*-application.yaml` | Argo CD Applications for test and prod |
| `kargo/` | Kargo Project `hello-world`, Warehouse, and Stages |
| `gitops/` | Deployments. Kargo updates the image tag in these files |

## GitHub secrets

On the GitHub repository, add these Actions secrets. Do not commit them.

| Secret | Value |
|---|---|
| `NEXUS_REGISTRY` | Nexus Docker host:port, for example `nexus.example.com:8082` |
| `NEXUS_USERNAME` | Nexus user that can push to the Docker hosted repository |
| `NEXUS_PASSWORD` | Password or token for that user |

A push that changes `hello-world/` runs the workflow. The page at test and prod shows `version 1.0.N` after promotion.

## Install

Run cleanup first if this cluster already has the earlier nginx demo. Kubernetes must be enabled in Docker Desktop. Scripts refuse to run unless the node name is `docker-desktop`.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install\install.ps1
```

In Argo CD you should see `kargo`, `kargo-config`, `hello-world-test`, and `hello-world-prod`. Kargo itself is the `kargo` Application. Its UI is separate.

After those Applications are Synced, create the local secrets. Do not paste the tokens into chat.

```powershell
.\install\kargo\create-git-secret.ps1 -Token "<github-pat>"
.\install\nexus\create-registry-secrets.ps1 -Registry "<host:port>" -Username "<user>" -Password "<password>"
```

The Git secret lets Kargo push promotion commits. The Nexus secrets let the cluster pull the image and let Kargo list tags. `insecureSkipTLSVerify` is set because Docker Desktop is behind TLS inspection. It is for this local demo only.

## UIs

These passwords are the public local-only values from the [Kargo quickstart](https://docs.kargo.io/quickstart).

| UI | URL | Login |
|---|---|---|
| Argo CD | http://localhost:31080 | `admin` / `admin` |
| Kargo | http://localhost:31081 | password `admin` |
| Hello World test | http://localhost:31083 | |
| Hello World prod | http://localhost:31084 | |

## What you should see

1. Argo CD shows the Kargo Helm release and the two Hello World Applications.
2. After the GitHub workflow publishes `1.0.N`, the Kargo project `hello-world` shows that Freight.
3. Test promotes on its own and commits the tag into `gitops/test/deployment.yaml`. Argo CD rolls test.
4. Prod stays on the old tag until you promote the prod Stage. That commits `gitops/prod/deployment.yaml`.

## Clean up

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install\cleanup.ps1
```

This removes Argo CD, Kargo, cert-manager, and the Hello World namespaces from Docker Desktop. It also pushes the image tags in Git back to `0.0.0`.
