# gitops-argocd-kargo-demo

Local Docker Desktop demo. Argo CD deploys public nginx from this repo. Kargo promotes a newer tag by committing to `main`.

Image: `public.ecr.aws/docker/library/nginx`

| Environment | Manifest | Starts at | Promotion |
|---|---|---|---|
| test | `gitops/test/deployment.yaml` | `1.27.5` | Automatic when a `1.28.x` tag exists |
| prod | `gitops/prod/deployment.yaml` | `1.27.5` | Manual in the Kargo UI, after test |

The Warehouse accepts only tags matching `^1\.28\.\d+$`. Alpine, perl, and other nginx tags are ignored.

## What is in this repo

| Path | Purpose |
|---|---|
| `install/install.ps1` | Installs cert-manager, Argo CD, and Kargo on the `docker-desktop` context |
| `install/cleanup.ps1` | Removes that install and puts the nginx tags back to `1.27.5` |
| `argocd/` | Applications that sync `gitops/test` and `gitops/prod` |
| `kargo/` | Project, Warehouse, and test/prod Stages |
| `gitops/` | Nginx Deployments. Kargo updates the image tag in these files |

## Install

Kubernetes must be enabled in Docker Desktop. Both scripts refuse to run unless the node name is `docker-desktop`.

PowerShell on this machine blocks local scripts. Allow them for the current window only. This does not change the system policy, and it ends when the window closes.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install\install.ps1
```

Create a GitHub personal access token that can push to this repo. Do not commit the token. Run this in the same window, after the policy command above.

```powershell
.\install\kargo\create-git-secret.ps1 -Token "<github-pat>"
```

Create that secret before the first promotion. Test promotion writes to `main` and fails without it.

## UIs

These passwords are the public local-only values from the [Kargo quickstart](https://docs.kargo.io/quickstart). They are for this Docker Desktop cluster.

| UI | URL | Login |
|---|---|---|
| Argo CD | http://localhost:31080 | `admin` / `admin` |
| Kargo | http://localhost:31081 | password `admin` |
| nginx test | http://localhost:31083 | |
| nginx prod | http://localhost:31084 | |

## What you should see

1. Both Argo CD apps are Synced. Both pods run tag `1.27.5`.
2. The Kargo Warehouse shows Freight for the newest `1.28.x` tag. Git is still on `1.27.5`.
3. The test Stage promotes on its own: one commit changes `gitops/test/deployment.yaml`, then Argo CD rolls the test pod.
4. Prod stays on `1.27.5` until you promote the prod Stage in the Kargo UI. That writes `gitops/prod/deployment.yaml`.

## Clean up for the next demo

After a demo, remove Argo CD, Kargo, cert-manager, and the nginx namespaces from Docker Desktop. Other workloads on that cluster are left in place. The script also commits and pushes the nginx tags back to `1.27.5`, because Kargo will have changed them on `main`.

Run it in a window where the execution policy was already set, or set it again:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install\cleanup.ps1
```

Then, for the next team, run `.\install\install.ps1` and create the Git secret again.
