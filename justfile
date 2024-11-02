build:
 cd services/foo && VERSION=1.0 skaffold build


cluster-init:
  minikube start --cpus 4 --memory 8192 --driver docker

cluster-delete:
  minikube delete

kargo-install:
  helm upgrade --install kargo \
  oci://ghcr.io/akuity/kargo-charts/kargo \
  --namespace kargo \
  --create-namespace \
  --set api.service.type=NodePort \
  --set api.service.nodePort=31444 \
  --set api.adminAccount.passwordHash='$2a$10$Zrhhie4vLz5ygtVSaif6o.qN36jgs6vjtMBdM6yrU1FOeiAAMMxOm' \
  --set api.adminAccount.tokenSigningKey=iwishtowashmyirishwristwatch \
  --wait

kargo-delete:
  helm uninstall kargo --namespace kargo

kargo-forward:
  minikube service -n kargo kargo-api --url

kargo-password:
  @kubectl -n kargo get secret kargo-api -o jsonpath="{.data.ADMIN_ACCOUNT_TOKEN_SIGNING_KEY}" | base64 -d

cert-manager-install:
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --set crds.enabled=true

cert-manager-delete:
  helm uninstall cert-manager --namespace cert-manager

argocd-install:
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

argocd-delete:
  kubectl delete namespace argocd

argocd-admin-password:
  @kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

argocd-forward: (argocd-admin-password)
  @echo ""
  @kubectl port-forward svc/argocd-server -n argocd 8080:443

argorollouts-install:
  kubectl create namespace argo-rollouts
  kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

argorollouts-delete:
  kubectl delete namespace argo-rollouts
