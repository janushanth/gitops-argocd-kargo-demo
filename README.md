# gitops-argocd-kargo-demo

Local Docker Desktop demo.

Argo CD installs Kargo, Nexus, Jenkins, and Goldilocks. Jenkins builds the Hello World image and pushes it to Nexus on this machine. Kargo sees that tag and promotes it. Argo CD deploys the new tag. Goldilocks watches every namespace except the Kubernetes system namespaces and its own. The label `goldilocks.fairwinds.com/enabled=true` is also set in Git on `hello-world-test`, `hello-world-prod`, `jenkins`, `nexus`, `kargo`, and `default`. It also installs metrics-server, which Docker Desktop does not include.

```text
Jenkins job hello-world
  -> Nexus  localhost:32082/hello-world:1.0.<time>
  -> Kargo Warehouse
  -> promote test (automatic) -> gitops/test
  -> promote prod (manual)    -> gitops/prod
  -> Argo CD rolls the pods
```

| Environment | Manifest | Starts at | Promotion |
|---|---|---|---|
| test | `gitops/test/deployment.yaml` | `0.0.0` | Automatic for tags `1.0.N` |
| prod | `gitops/prod/deployment.yaml` | `0.0.0` | Manual in the Kargo UI, after test |

The registry is `localhost:32082`. Docker already allows plain HTTP to localhost, so the Docker Engine JSON stays as it is. The same host and port are in the Jenkins job, the Warehouse, and the Deployments.

## What is in this repo

| Path | Purpose |
|---|---|
| `hello-world/Dockerfile` | Hello World page. The image tag is written into the page |
| `jenkins/Dockerfile` | Jenkins plus the plugins and a Docker client. Built on the laptop by the install script |
| `platform/jenkins` | Jenkins and a Docker daemon in the same pod |
| `platform/nexus` | Nexus, and a Job that creates the Docker hosted repository |
| `install/goldilocks/chart/goldilocks` | Goldilocks 11.2.1 Helm chart, including VPA. Argo CD reads it from this folder |
| `install/install.ps1` | Installs cert-manager and Argo CD. Argo CD installs Kargo, Nexus, Jenkins, and Goldilocks |
| `install/kargo/chart/kargo` | Kargo 1.12.5 Helm chart. Argo CD reads it from this folder |
| `install/cleanup.ps1` | Removes the demo and puts the image tag back to `0.0.0` |
| `argocd/` | Argo CD Applications |
| `kargo/` | Kargo Project `hello-world`, Warehouse, Stages, and the local registry credential |
| `gitops/` | Deployments. Kargo updates the image tag in these files |

Local demo passwords are in the manifests: Jenkins `admin` / `admin`, Nexus `admin` / `admin123`. The GitHub token Kargo uses to push commits stays out of Git.

## Before install

Kubernetes is enabled in Docker Desktop. The script refuses to run unless the node name is `docker-desktop`. No Docker Engine change is required.

The install pulls every image it needs before the pods start, so a fresh laptop does not sit in `ContainerCreating` while a large image downloads. Each pull is retried three times. The first run takes longer because the images are downloaded.

Argo CD clones `https://github.com/janushanth/gitops-argocd-kargo-demo.git` branch `main`. Push this repo to that branch before you install. A local-only commit is invisible to Argo CD, and the install will sync the older files that still pull Kargo from ghcr.io.

## Install

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install\install.ps1
```

The script downloads the Jenkins plugins on the laptop, builds `gitops-demo-jenkins:local`, installs Argo CD, and waits until Nexus has created the Docker repository and Jenkins is up. The plugin download stays on the laptop because Java inside the image build does not trust the company certificate.

Then create the Git credential. Do not paste the token into chat.

```powershell
.\install\kargo\create-git-secret.ps1 -Token "<github-pat>"
```

In Argo CD you should see `kargo`, `kargo-config`, `nexus`, `jenkins`, `goldilocks`, `hello-world-test`, and `hello-world-prod`.

Open Jenkins at http://localhost:32080 and run the job `hello-world`. The first pods stay on tag `0.0.0` until that job has pushed an image and Kargo has promoted it.

## UIs

| UI | URL | Login |
|---|---|---|
| Argo CD | http://localhost:31080 | `admin` / `admin` |
| Kargo | http://localhost:31081 | password `admin` |
| Jenkins | http://localhost:32080 | `admin` / `admin` |
| Nexus | http://localhost:32081 | `admin` / `admin123` |
| Hello World test | http://localhost:31083 | |
| Hello World prod | http://localhost:31084 | |
| Goldilocks | http://localhost:31085 | |

## What you should see

1. The Jenkins job pushes `localhost:32082/hello-world:1.0.<time>`.
2. The Kargo project `hello-world` shows that Freight.
3. Test promotes on its own and commits the tag into `gitops/test/deployment.yaml`. Argo CD rolls test.
4. Prod stays on the old tag until you promote the prod Stage. That commits `gitops/prod/deployment.yaml`.

The page shows `version 1.0.<time>` after the pod is running.

## Updating the Kargo chart

The chart is in this repo because the Argo CD repo-server cannot reach `ghcr.io` through the corporate TLS inspection. To change the version, pull it on the laptop into the same folder. Then check that the values in `argocd/kargo-application.yaml` still match the new chart's value names.

```powershell
helm pull oci://ghcr.io/akuity/kargo-charts/kargo --version <new-version> --untar --untardir install/kargo/chart
```

## Clean up

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install\cleanup.ps1
```

This removes Argo CD, Kargo, Nexus, Jenkins, Goldilocks, cert-manager, and the Hello World namespaces. It also pushes the image tags in Git back to `0.0.0`.
