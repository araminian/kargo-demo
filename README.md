# KARGO

Kargo is a tool for managing the promotion of artifacts across multiple stages of a delivery pipeline.

We define a `Delivery Pipeline` as a DAG (Directed Acyclic Graph) of `Stages`. Kargo will checking for new `Freight` in the `Warehouse` and will promote it to the next `Stage` in the pipeline. At the end of the pipeline, we can define a `Verification` step to check if the `Promotion` is successful.


So to make it simple, let's give an example:

We have a service called `foobar`. We need to deploy this to `dev` and `prod` environments. By each commit to the `Repo`, we build the docker image and push it to the `Docker Registry`. 

We define those stages in `Kargo` with following steps(`Promotion Steps`):
- Clone service repo
- Use image from the registry
- Generate manifests via using Helm
- Push manifests to the GitOps repository
- Run integration tests (which are handled by `Argo Rollouts`)

So we need to tell `Kargo` whenever we have a new images in the registry, so it means we have a new version of the service, so we need to deploy it to those stages. So we define a `Warehouse` that will watch the `Docker Registry` and whenever there is a new image, it will create a new `Freight`.

In `stage` we define that `stage` should watch for a new `Freight`, it will run the `Promotion` process/release process.



## Requirements

- Argo CD -> Kargo is intended to be installed into the same cluster as the Argo CD control plane
- Argo Rollouts
- Cert Manager


## Installation

```bash
just cert-manager-install
just argocd-install
just argorollouts-install
just kargo-install
```
## Key Concepts

### Project
`Project` is a collection of related Kargo resources that describe one or more delivery pipelines. (Looks like ArgoCD Project). RBAC is enforced at the project level.:24

- `Project` is cluster-scoped.
- By creating a `Project` , Kargo will create a namespace with the same name. All resources belonging to a `Project` should be grouped in that namespace.
- Deletion of a `Project` or `Namespace` will trigger deletion of `Namespace` or `Project` resources respectively.

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: kargo-demo
```

We can define optional project-level configuration. We have only `Promotion Policy` that describes, if a `Stage` is eligible for automatic promotion, whenever a `Freight` is created in the `Warehouse`.

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: kargo-demo
spec:
  promotionPolicies:
  - stage: test
    autoPromotionEnabled: true
  - stage: uat
    autoPromotionEnabled: true
```

### Stage

`Stage` (test , prod) denotaes sevice's purpose and not necessarily the location!
`Stages` can be linked together in a DAG (Directed Acyclic Graph) to form a `Delivery Pipeline`.

For instanse: `edge` -> `prestage` -> `stage` -> `prepord` -> `prod`

**P.S.** `Stage` looks like Github Action `Job`.

`Stage` resource's `spec` contains three main areas of concerns:
- `Requested freight`
- `Promotion template`
- `Verification`

#### Requested freight

It's describeing one or more `Freight` that `Stage`'s promotion process, will operate on. We can define the source from which `Freight` will be fetched. This source can be `Warehouse` or `upstream` stages.

- `Freight` are described by an `origin` field having `kind` and `name` subfields instead of being described only by the name of a `Warehouse`.

For each `Stage` , Kargo will preiodically check for new available `Freights` to promote the `Stage`.

When a `Stage` accepts `Freight` directly from its origin, all new `Freight` created by that origin (e.g. a `Warehouse` ) are immediately available for promotion to that `Stage`.

When a `Stage` accepts `Freight` from an `upstream` stage, that `Freight` can be used to promote the `Stage` only if that `Freight` is verified by at least one `upstream` stage. User can manually approve `Freight` to be promoted to a `Stage`, so no need to wait for verification.



In the following example, the `test` `Stage` requests `Freight` that has originated from the `my-warehouse` `Warehouse` and indicates that it will accept new `Freight` directly from that origin:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: test
  namespace: kargo-demo
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: my-warehouse
    sources:
      direct: true
  # ...
```

In this example, the `uat` `Stage` requests `Freight` that has originated from the `my-warehouse` `Warehouse`, but indicates that it will accept such `Freight` only after it has been verified in the `test` `Stage`:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: uat
  namespace: kargo-demo
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: my-warehouse
    sources:
      stages:
      - test
  # ...
```


`Stages` may also request `Freight` from multiple sources. The following example illustrates a `Stage` that requests `Freight` from both a `microservice-a` and `microservice-b` `Warehouse`:


```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: test
  namespace: kargo-demo
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: microservice-a
    sources:
      direct: true
  - origin:
      kind: Warehouse
      name: microservice-b
    sources:
      direct: true
  # ...
```

**TIP** : By requesting `Freight` from multiple sources, a `Stage` can effectively participate in multiple pipelines that may each deliver different collections of artifacts independently of the others. At present, this is most useful for the delivery of microservices that are developed and deployed in parallel.


**P.S.** : It seems that if we want to use that `stage` in a pipeline to deloy 100 microservices, we need to create `100` `requestedFreight entries` ! Maybe it's wrong and there is a better way to do it.`:warning:


#### Promotion template
`Promotion template` describes how to transition a `Freight` to a `Stage`. `steps` field describe the discrete steps of a promotion process in detail.

For example:

1. Clone a Git repository containing Kubernetes manifests and Kustomize configuration, checking out two different branches to two different directories.

2. Clears the contents of one working tree, with intentions to fully replace its contents.

3. Runs the equivalent of kustomize edit set image to update a kustomization.yaml file with a reference to an updated public.ecr.aws/nginx/nginx container image.

4. Renders the updated manifests using the equivalent of kustomize build.

5. Commits the updated manifests and pushes them to the stage/test of the remote repository.

6. Forces Argo CD to sync the kargo-demo-test application to the latest commit of the stage/test branch.

```yaml
promotionTemplate:
  spec:
    steps:
    - uses: git-clone #1
      config:
        repoURL: https://github.com/example/repo.git
        checkout:
        - fromFreight: true
          path: ./src
        - branch: stage/test
          create: true
          path: ./out
    - uses: git-clear #2
      config:
        path: ./out
    - uses: kustomize-set-image #3
      as: update-image
      config:
        path: ./src/base
        images:
        - image: public.ecr.aws/nginx/nginx
    - uses: kustomize-build #4
      config:
        path: ./src/stages/test
        outPath: ./out
    - uses: git-commit #5
      as: commit # Here we can set name for this step
      config:
        path: ./out
        messageFromSteps:
        - update-image
    - uses: git-push #6
      config:
        path: ./out
        targetBranch: stage/test
    - uses: argocd-update #7
      config:
        apps:
        - name: kargo-demo-test
          sources:
          - repoURL: https://github.com/example/repo.git
            desiredCommitFromStep: commit
```

`Promotion Steps` [Library](https://docs.kargo.io/references/promotion-steps)

**P.S.** : Those `Promotion steps` are look like `Github Actions`, and there are steps that we run in Github Actions' `Jobs`.


#### Verification

We can define optional `verification` processes that should be execured after a `Promotion` has succesfully deployed `Freight` to a `Stage` , if applicable, after the `Stage` has reached a `healthy` state.

Verification processes are defined through references to one or more `Argo Rollouts AnalysisTemplate` resources that reside in the same `Project/Namespace` as the `Stage` resource.

**P.S.** : It seems that `integration tests` should be defined in the `Argo Rollouts AnalysisTemplate` resource. But the issue is we won't have visibility for logs! maybe Kargo will have some solution for this.

The following example depicts a `Stage` resource that references an `AnalysisTemplate` named `kargo-demo` to validate the `test` `Stage` after any successful `Promotion`:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: test
  namespace: kargo-demo
spec:
  # ...
  verification:
    analysisTemplates:
    - name: kargo-demo
```

It is also possible to specify additional labels, annotations, and arguments that should be applied to `AnalysisRun` resources spawned from the referenced `AnalysisTemplate`:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: test
  namespace: kargo-demo
spec:
  # ...
  verification:
    analysisTemplates:
    - name: kargo-demo
    analysisRunMetadata:
      labels:
        foo: bar
      annotations:
        bat: baz
    args:
    - name: foo
      value: bar
```

An `AnalysisTemplate` could be as simple as the following, which merely executes a Kubernetes `Job` that is defined inline:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: kargo-demo
  namespace: kargo-demo
spec:
  metrics:
  - name: test
    provider:
      job:
        metadata:
        spec:
          backoffLimit: 1
          template:
            spec:
              containers:
              - name: test
                image: alpine:latest
                command:
                - sleep
                - "10"
              restartPolicy: Never
```

A `Stage` resource's `status` field records:

- The current phase of the `Stage` resource's lifecycle.
- Information about the last `Promotion` and any in-progress `Promotion`.
- History of `Freight` that has been deployed to the `Stage` (from most to least recent) along with the results of any associated verification processes.
- The health status of any associated Argo CD Application resources.

### Freight

A single `piece of freight` is a set of references to one or more versioned artifacts:
- `Container images`
- `K8S manifests`
- `Helm Charts`

`Freight` is somehow meta-artifact. Freight is what Kargo seeks to progress from one stage to another.

`Freight` resources are immutable except for their `alias` field and `status` subresource .

A `Freight` resource's `metadata.name` field is a SHA1 hash of a canonical representation of the artifacts referenced by the `Freight` resource. (This is enforced by an admission webhook.) The `metadata.name` field is therefore a "fingerprint", deterministically derived from the `Freight`'s contents.

To provide a human-readable identifier for a `Freight` resource, a `Freight` resource has an `alias` field. This `alias` is a human-readable string that is unique within the `Project` to which the `Freight` belongs. Kargo automatically generates unique `aliases` for all `Freight` resources, but users may update them to be more meaningful.

A `Freight` resource's `status` field records a list of `Stage` resources in which the `Freight` has been verified and a separate list of `Stage` resources for which the `Freight` has been manually approved.


**P.S.** : It seems that we don't need to directly interact with `Freight` resource.


### Warehouse

`Warehouse` is source of `Freight`. A `Warehouse` subscribes to one or more:
- `Git Repositories`
- `Container Registries`
- `Helm Repositories`

Any update in any repository to which a `Warehouse` subscribes, `Warehouse` will detect it and create a `Freight` for it.

A `Warehouse` resource's most important field is its `spec.subscriptions` field. This field describes the subscriptions to the sources of `Freight`.

The following example shows a `Warehouse` resource that subscribes to a container image repository and a Git repository:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: my-warehouse
  namespace: kargo-demo
spec:
  subscriptions:
  - image:
      repoURL: public.ecr.aws/nginx/nginx
      semverConstraint: ^1.26.0
  - git:
      repoURL: https://github.com/example/kargo-demo.git
```

The following example demonstrates a `Warehouse` with a Git repository subscription that will only produce new `Freight` when the latest commit (selected by the applicable commit selection strategy) contains changes in the `apps/guestbook` directory since the last piece of `Freight` produced by the `Warehouse`:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: my-warehouse
  namespace: kargo-demo
spec:
  subscriptions:
  - git:
      repoURL: https://github.com/example/kargo-demo.git
      includePaths:
      - apps/guestbook
```

The next example demonstrates the opposite: a `Warehouse` with a Git repository subscription that will only produce new `Freight` when the latest commit (selected by the applicable commit selection strategy) contains changes to paths other than the repository's `docs/` directory:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: my-warehouse
  namespace: kargo-demo
spec:
    subscriptions:
    - git:
        repoURL: https://github.com/example/kargo-demo.git
      excludePaths:
      - docs
```

**P.S.** : This feature is very useful for us, as we have Monorepo `Gitops` repository.


### Promotion

`Promotion` is a request to move a piece of `Freight` into a specific `Stage`.

A `Promotion` resource's two most important fields are its `spec.freight` and `spec.stage` fields, which respectively identify a piece of `Freight` and a target `Stage` to which that `Freight` should be promoted.

**P.S.** : It seems that we don't need to directly interact with `Promotion` resource.




## Argo CD

We should tell Kargo, which `application` belongs to which `stage`, we should do it by adding `annotations` to `Argo CD Application` resource.

```yaml
annotations:
        kargo.akuity.io/authorized-stage: <Project>:<Stage>
```


## Kargo GIT Access

We need to provide Kargo with access to the `Git` repository.

```yaml
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: kargo-demo-repo
  namespace: kargo-demo
  labels:
    kargo.akuity.io/cred-type: git
stringData:
  repoURL: ${GITOPS_REPO_URL}
  username: ${GITHUB_USERNAME}
  password: ${GITHUB_PAT}
```
**P.S.**: Can we define this cluster-wide? for whole organization?



## Questions

- Based on multiple examples that i've seen, it's better to generate manifests in the `stage` as `Promotion step`. The idea is:
  - Build the image in `GitHub Actions` and push it to the `Registry`.
  - Having `Warehouse` subscribed to the `Registry`, Kargo will create `Freight` with the image.
  - Based on that `Freight`, We would generate manifests in the `stage` and apply them. Push them to the `GitOps` repository.
  - Then `Kargo` will run the `Verification` step to check if the `Promotion` is successfu.

So if we want to implement this:
- We need to find a way to generate manifests in the `stage`. Challenges:
  - not possible to use `Skaffold` since we can't use custom steps, and have to use predefined steps.
  - A lot of `ENVs` to be set!
  - Clone the service repo in the `stage`, but which commit? it can be hard since image might be built based on previous commit! or make our charts versioned and put them to the `Chart Museum` and use them in the `stage`. but then we need to handle the `values files` for each service.
- Integration tests should be run as `Argo Rollouts Analysis`, Challenges:
  - We don't have visibility to steps or it's hard to access them!
  - IAM permission to access GCS bucket for storing test results!
- How we handle multiple updates in the same `Freight`? Parallel? or cancel others?

If we generate manifests like now on `GitHub Actions`, we don't need to care about the above challenges, but what is the point of having `Kargo` then? :thinking: , `Kargo` just watch the `GitOps` repository and sync the apps, which not make any sense. Since Kargo idea is to promoting the `Freight`, but here we don't have any `Freight`, since we are already generating the manifests on `GitHub Actions`.


