#!/bin/bash

##############################################################################
# -- FUNCTIONS --
info() {
    printf "\n+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
    printf "\nINFO: $@\n"
    printf "\n+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
}
deploy_operator() # (subscription yaml file, operator name, namespace)
{
    oc apply -f $1 -n $3
    LOOP="TRUE"
    echo "waiting for operator to be in Succeeded state"
    while [ $LOOP == "TRUE" ]
    do
        # get the csv name
        #RESOURCE=$(oc get subscription $2 -n $3 -o template --template '{{.status.currentCSV}}')
        RESOURCE=$2
        # get the status of csv
        #RESP=$(oc get csv $RESOURCE -n $3  --no-headers 2>/dev/null)
        RC=$(echo $?)
        STATUS=""
        if [ "$RC" -eq 0 ]
        then
            STATUS=$(oc get csv $RESOURCE -n $3 -o template --template '{{.status.phase}}')
            RC=$(echo $?)
        fi
        # Check the CSV state
        if [ "$RC" -eq 0 ] && [ "$STATUS" == "Succeeded" ]
        then
            echo "$2 operator deployed!"
            LOOP="FALSE"
        fi
    done
}
#-----------------------------------------------------------------------------

##############################################################################
# -- ENVIRONMENT --
NS_CMP=sk-workshop-components
NS_DEV=sk-app-dev
NS_TEST=sk-app-test
NS_PROD=sk-app-prod
GITEA_HOSTNAME=
ARGO_URL=
ARGO_PASS=
#-----------------------------------------------------------------------------

##############################################################################
# -- EXECUTION --
#-----------------------------------------------------------------------------

info "Starting installation"

info "Creating namespaces"
oc new-project $NS_CMP
oc new-project $NS_DEV
oc new-project $NS_TEST
oc new-project $NS_PROD
oc policy add-role-to-user system:image-puller system:serviceaccount:$NS_TEST:default -n $NS_DEV
oc policy add-role-to-user system:image-puller system:serviceaccount:$NS_PROD:default -n $NS_DEV


info "Deploying and configuring GITEA"
oc apply -f workshop-environment/gitea/gitea_deployment.yaml -n $NS_CMP
GITEA_HOSTNAME=$(oc get route gitea -o template --template='{{.spec.host}}' -n $NS_CMP)
sed "s/@HOSTNAME/$GITEA_HOSTNAME/g" workshop-environment/gitea/gitea_configuration.yaml | oc create -f - -n $NS_CMP
oc rollout status deployment/gitea -n $NS_CMP
sed "s/@HOSTNAME/$GITEA_HOSTNAME/g" workshop-environment/gitea/setup_job.yaml | oc apply -f - --wait -n $NS_CMP
oc wait --for=condition=complete job/configure-gitea --timeout=60s -n $NS_CMP

info "Deploying and configuring OpenShift pipelines"
deploy_operator workshop-environment/tekton/operator_sub.yaml openshift-pipelines-operator-rh.v1.11.0 openshift-operators
sleep 30
oc policy add-role-to-user edit system:serviceaccount:$NS_CMP:pipeline -n $NS_DEV
oc policy add-role-to-user edit system:serviceaccount:$NS_CMP:pipeline -n $NS_TEST
oc policy add-role-to-user edit system:serviceaccount:$NS_CMP:pipeline -n $NS_PROD

info "Deploying and configuring GitOps"
deploy_operator workshop-environment/gitops/operator_sub.yaml openshift-gitops-operator.v1.9.0  openshift-operators
sleep 15
oc apply -f workshop-environment/gitops/roles.yaml
ARGO_URL=$(oc get route openshift-gitops-server -ojsonpath='{.spec.host}' -n openshift-gitops)
ARGO_PASS=$(oc get secret openshift-gitops-cluster -n openshift-gitops -ojsonpath='{.data.admin\.password}' | base64 -d)
oc policy add-role-to-user edit system:serviceaccount:$NS_CMP:pipeline -n openshift-gitops

info "Creating application initial version"
oc new-build  openshift/ubi8-openjdk-11:1.3~http://$GITEA_HOSTNAME/gitea/application-source --name=quarkus-app -n sk-app-dev
oc wait --for=condition=complete build/quarkus-app-1 -n sk-app-dev
sleep 20
oc tag sk-app-dev/quarkus-app:latest quarkus-app:1.0.0-initial -n sk-app-dev
oc get is -n sk-app-dev

info "Creating argocd application environments"
oc apply -f application-deploy/argo/quarkus-app.yaml -n openshift-gitops

oc apply -f application-cicd/resources -n $NS_CMP
PUSH_WH=$(oc get eventlistener quarkus-app-push-listener -o jsonpath='{.status.address.url}' -n $NS_CMP)
PR_WH=$(oc get eventlistener quarkus-app-pr-listener -o jsonpath='{.status.address.url}' -n $NS_CMP)

##############################################################################
# -- INSTALATION INFO --
#-----------------------------------------------------------------------------
printf "\n+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
printf "\nINSTALATIO COMPLETED!!\n"
printf "\n"
printf "OPENSHIFT NAMESPACES: \n"
printf "  - components: $NS_CMP\n"
printf "  - dev: $NS_DEV\n"
printf "  - test: $NS_TEST\n"
printf "  - production: $NS_PROD\n"
printf "\n"
printf "GITEA: \n"
printf "  - url: http://$GITEA_HOSTNAME\n"
printf "  - user: gitea\n"
printf "  - password: openshift\n"
printf "\n"
printf "ARGO: \n"
printf "  - url: https://$ARGO_URL\n"
printf "  - user: admin\n"
printf "  - password: $ARGO_PASS\n"
printf "\n"
printf "PIPELINES: \n"
printf "  - push webhook: $PUSH_WH\n"
printf "  - pull request webhook: $PR_WH\n"
printf "\n"
printf "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n"


