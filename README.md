# tekton-workshop

Tekton pipelines workshop

## Prerequisites

- oc client.
- openshift cluster with admin rights.

## Installation

Open a terminal abd login into OpenShift using an user with admin rights.

Execute `install.sh` script. The final output contains the demo installation information. Example:

```
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

INSTALATIO COMPLETED!!

OPENSHIFT NAMESPACES:
  - components: ${YOUR_NAME_INITIAL}-workshop-components
  - dev: ${YOUR_NAME_INITIAL}-app-dev
  - test: ${YOUR_NAME_INITIAL}-app-test
  - production: ${YOUR_NAME_INITIAL}-app-prod

GITEA:
  - url: http://gitea-${YOUR_NAME_INITIAL}-workshop-components.apps.cluster-7mjqq.7mjqq.sandbox1856.opentlc.com
  - user: gitea
  - password: openshift

ARGO:
  - url: https://openshift-gitops-server-openshift-gitops.apps.cluster-7mjqq.7mjqq.sandbox1856.opentlc.com
  - user: admin
  - password: iDcS0auoFe5ZE4G3NMpbQvRX7CJgxYPw

PIPELINES:
  - push webhook: http://el-quarkus-app-push-listener.${YOUR_NAME_INITIAL}-workshop-components.svc.cluster.local:8080
  - pull request webhook: http://el-quarkus-app-pr-listener.${YOUR_NAME_INITIAL}-workshop-components.svc.cluster.local:8080

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
```

Configure gitea webhooks for application push events in master branch (using installation information values):

- Open **GITEA url** and login.
- Open `application-source`
- Create a webhook in `Settings > Webhooks > Add Webhook`
- Target URL must be **PIPELINES push webhook**
- HTTP Method must be `POST`
- POST Content Type must be `application/json`
- Secret can be any value
- Trigger On `Push Events`
- Branch filter must be `master`

Configure gitea webhooks for deploy pull request events (using installation information values):

- Open **GITEA url** and login.
- Open `application-deploy`
- Create a webhook in `Settings > Webhooks > Add Webhook`
- Target URL must be **PIPELINES pull request**
- HTTP Method must be `POST`
- POST Content Type must be `application/json`
- Secret can be any value
- Trigger On `Custon Events` and mark `Pull Request`

Login into ArgoCD and manually sync applications.

## CICD Demo

> NOTE: Some of the following pipeline tasks are a mock and will be completed later on.

Validate applications are working as expected:

```sh
# dev
DEV_URL=$(oc get route quarkus-app -n ${YOUR_NAME_INITIAL}-app-dev -o jsonpath='{.status.ingress[0].host}')
curl http://$DEV_URL/app/info

# test
TEST_URL=$(oc get route quarkus-app -n ${YOUR_NAME_INITIAL}-app-test -o jsonpath='{.status.ingress[0].host}')
curl http://$TEST_URL/app/info

# prod
PROD_URL=$(oc get route quarkus-app -n ${YOUR_NAME_INITIAL}-app-prod -o jsonpath='{.status.ingress[0].host}')
curl http://$PROD_URL/app/info
```

Open `application-source` repository and modify the application `pom.xml` version:

```xml
<version>1.0.1</version>
```

Commit changes. That push event must trigger tekton `ci-pipeline`:

![image](images/ci.png)

The result of the `ci-pipeline` is a new image tagged with current version and a pull request in `application-deploy` repository to deploy in **dev** environment:

![image](images/dev-pr.png)

Merge pull request. That event must trigger tekton `cd-pipeline`:

![image](images/cd-dev.png)

Validate new version has been deployed:
```sh
curl http://$DEV_URL/app/info

"dev" - quarkus-app:1.0.1
```

The `cd-pipeline` also has created a pull request in `application-deploy` repository to deploy in **test** environment:

![image](images/test-pr.png)

Merge pull request. That event must trigger tekton `cd-pipeline`:

![image](images/cd-test.png)

Validate new version has been deployed:
```sh
curl http://$TEST_URL/app/info

"test" - quarkus-app:1.0.1
```

The `cd-pipeline` also has created a new tag with `-release` appended and a pull request in `application-deploy` repository to deploy in **prod** environment:

![image](images/pr-prod.png)

Merge pull request. That event must trigger tekton `cd-pipeline`:

![image](images/cd-prod.png)

Open ArgoCD and review **prod** application (refresh if needed):

![image](images/sync-1.png)


The difference is the new image:

![image](images/sync-2.png)

Sync manually the application and validate:

```sh
curl http://$PROD_URL/app/info

"prod" - quarkus-app:1.0.1
```

## Re-Installation

```sh
# Delete argo applications
oc delete application.argoproj.io/quarkus-app -n openshift-gitops

# Delete namespaces
oc delete project ${YOUR_NAME_INITIAL}-workshop-components
oc delete project ${YOUR_NAME_INITIAL}-app-dev
oc delete project ${YOUR_NAME_INITIAL}-app-test
oc delete project ${YOUR_NAME_INITIAL}-app-prod
```

> NOTE: wait until all namespaces are removed sucessfully an proceed with installation.

## Tekton Overview

> NOTE: tkn client required!

Create a namespace:

```sh
oc new-project tekton-overview
```

Create the following task:

```yaml
cat << EOF | oc apply -f  -
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: demo-task
spec:
  params:
    - name: MESSAGE
  results:
    - name: MESSAGE_DATE
  steps:
    - name: print-message
      image: registry.access.redhat.com/ubi8/ubi-minimal:8.3
      script: |
        echo $(params.MESSAGE)
    - name: get-date
      image: registry.access.redhat.com/ubi8/ubi-minimal:8.3
      script: |
        DATE=$(date)
        echo $DATE > $(results.MESSAGE_DATE.path)
        echo $DATE
EOF
```

Create and test the task:

```sh
tkn task list
tkn task start demo-task
tkn taskrun logs demo-task-run-j662m -f -n tekton-overview
oc get pods
oc logs demo-task-run-xxxxx-pod
oc logs demo-task-run-xxxxx-pod -c step-print-message
oc logs demo-task-run-xxxxx-pod -c step-maven-version
```

Create a pipeline:

```yaml
cat << EOF | oc apply -f  -
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: demo-pipeline
spec:
  params:
    - name: MESSAGE
  tasks:
    - name: task-1
      taskRef:
        kind: Task
        name: demo-task
      params:
        - name: MESSAGE
          value: $(params.MESSAGE)
    - name: task-2
      runAfter:
        - task-1
      taskRef:
        kind: Task
        name: demo-task
      params:
        - name: MESSAGE
          value: "$(tasks.task-1.results.MESSAGE_DATE)"
EOF
```

Create and test the pipeline:

```sh
tkn pipeline list
tkn pipeline start demo-pipeline
tkn pipelinerun logs demo-pipeline-run-xxxxx -f -n tekton-overview
tkn pipeline list
oc get pods
```
