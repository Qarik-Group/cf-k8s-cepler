# Cepler templates

This repository introduces the [cepler-templates](https://github.com/bodymindarts/cepler-templates) project via the example of deploying [cf-for-k8s](https://github.com/cloudfoundry/cf-for-k8s) using `github-actions` as the CD driver.

## Introduction

Deploying software to multiple environments (such as dev / staging / production) introduces operational complexity that requires explicit managing in order to ensure parity between environments.
Previously I wrote an [article](https://www.starkandwayne.com/blog/introducing-cepler/) introducing how you can use [cepler](https://github.com/bodymindarts/cepler) to significantly reduce this overhead (and it is recommended to read that first).

In this article we will use [cepler-templates](https://github.com/bodymindarts/cepler-templates) to automate the execution of the `cepler check`, `cepler prepare`, `cepler record` cycle to deploy [cf-for-k8s](https://github.com/cloudfoundry/cf-for-k8s) using github actions.

## Prerequisites

If you want to follow along with the demo you will need access to 2 publicly accessible kubernetes clusters representing 2 environments that we want to deploy cf to.

If you want the resulting cf to be fully functional you will also need a dns name you can use to access cf.

## Preparation

First we will clone the [cf-for-k8s](https://github.com/cloudfoundry/cf-for-k8s) repo and generate some values we need.

```
$ git clone https://github.com/cloudfoundry/cf-for-k8s && cd cf-for-k8s
$ git checkout v1.0.0
$ ./hack/generate-values.sh -d <testflight-dns> > testflight-values.yml
$ ./hack/generate-values.sh -d <staging-dns> > staging-values.yml
```

Then we will create a new repository to store the files needed to deploy cf-for-k8s.

- Go to github.com and create a new repository called cf-k8s-cepler.
```
$ cd ..
$ git clone git@github.com:your-github-org/cf-k8s-cepler.git && cd cf-k8s-cepler
```

## Config files

We will use [vendir](https://github.com/k14s/vendir#vendir) to sync the files we need from cf-for-k8s:
```
$ mkdir k8s
$ cat <<EOF > vendir.yml
---
apiVersion: vendir.k14s.io/v1alpha1
kind: Config
minimumRequiredVersion: 0.8.0
directories:
- path: k8s
  contents:
  - path: cf-for-k8s
    git:
      url: https://github.com/cloudfoundry/cf-for-k8s
      ref: 73745a3a9891b0d1ceec646c184b09650c626bdb
    includePaths:
    - config/**/*
EOF
$ vendir sync
$ git add . && git commit -m 'Sync cf-for-k8s config files'
```

Now we need to add the values we generated in the previous step and append some dockerhub credentials to it. Don't actually add your password here, that will be injected via the github secrets mechanism.
```
$ cp ../cf-for-k8s/testflight-values.yml ./k8s/
cat <<EOF >> k8s/testflight-values.yml
app_registry:
  hostname: https://index.docker.io/v1/
  repository_prefix: "<dockerhub_username>"
  username: "<dockerhub_username>"
  password: DUMMY
EOF
$ cp ../cf-for-k8s/staging-values.yml ./k8s/
cat <<EOF >> k8s/staging-values.yml
app_registry:
  hostname: https://index.docker.io/v1/
  repository_prefix: "<dockerhub_username>"
  username: "<dockerhub_username>"
  password: DUMMY
EOF
$ git add . && git commit -m 'Add environment-values'
```

Next we will add a `cepler.yml` and `ci.yml` which are needed to generate the deployment pipeline.
```
$ cat <<EOF > cepler.yml
environments:
  testflight:
    latest:
    - k8s/cf-for-k8s/**/*
    - k8s/testflight-values.yml
  staging:
    passed: testflight
    propagated:
    - k8s/cf-for-k8s/**/*
    latest:
    - k8s/staging-values.yml
EOF
$ cat <<EOF > ci.yml
cepler:
  config: cepler.yml

driver:
  type: github
  repo:
    access_token: ${{ secrets.ACCESS_TOKEN }}
    branch: master
  secrets:
    app_registry:
      password: ${{ secrets.DOCKERHUB_PASSWORD }}

processor:
  type: ytt
  files:
  - k8s/cf-for-k8s/config
  - k8s/*.yml

executor:
  type: kapp
  environments:
    testflight:
      app_name: testflight-cf
      ca_cert: ${{ secrets.TESTFLIGHT_CA }}
      server: ${{ secrets.TESTFLIGHT_SERVER }}
      token: ${{ secrets.TESTFLIGHT_TOKEN }}
    staging:
      app_name: staging-cf
      ca_cert: ${{ secrets.STAGING_CA }}
      server: ${{ secrets.STAGING_SERVER }}
      token: ${{ secrets.STAGING_TOKEN }}
EOF
$ git add . && git commit -m 'Add cepler.yml and ci.yml'
```

The `cepler.yml` file configures the order in which the environments are deployed and which files belong to each environment.

The `ci.yml` tells the `cepler-templates` processor how the CD pipeline should be built. In this case we are using `github` as a driver `ytt` as a processor and `kapp` as an executor.

## Secrets

Now go to https://github.com/your-github-org/cf-k8s-cepler/settings/secrets and add the following secrets:
- `DOCKERHUB_PASSWORD` - password to signin to dockerhub
- `ACCESS_TOKEN` - a personal access token that can push to this repository. You can create one under https://github.com/settings/tokens.
- `TESTFLIGHT_SERVER` - the endpoint of the `testflight` kubernetes cluster.
- `TESTFLIGHT_CA` - the ca cert for the kubernetes cluster you want to use for the `testflight` environment.
- `STAGING_SERVER` - the endpoint of the `staging` kubernetes cluster.
- `STAGING_CA` - the ca cert for the kubernetes cluster you want to use for the `staging` environment.

To gain access we also need a token from a service account that has the required permissions for deploying cf:
```
$ kubectl config set-context <cluster>
$ kubectl apply -f https://raw.githubusercontent.com/starkandwayne/cf-k8s-cepler/master/deployer-account.yml
$ secret_name=$(kubectl get serviceaccount cf-deployer -o json | jq -r '.secrets[0].name')
$ kubectl get secrets ${secret_name} -o json | jq -r '.data.token' | base64 --decode
<token>
```
Copy the resulting token into the `TESTFLIGHT_TOKEN` and `STAGING_TOKEN` secrets respectivly.

## Configuring github-actions

Now everything is in place and we can create our continuous deployment setup:
```
$ workflows_dir=.github/workflows
$ mkdir -p ${workflows_dir}
$ docker run -v $(pwd):/workspace/inputs -it bodymindarts/cepler-templates:0.2.0 > ${workflows_dir}/deploy-cf-environments.yml
$ git add . && git commit -m 'Add deploy-cf-environments workflow'
```

## Deployment

Once you have pushed your repo upstream to github an action should be kicked off:
```
$ git push -u origin master
```

You can follow the progress of the triggered workflows here: https://github.com/your-github-org/cf-k8s-cepler/actions

If you click on the latest commit you will be able to drop down the `cepler-deploy` workflow.
There are 2 jobs `deploy-testflight` and `deploy-staging`.

The intial run of `deploy-staging` should fail since it depends on `testflight` having been completed succesfully at least once. If you follow the `deploy-testflight` job the deployment should complete correctly and produce an updated cepler state:
```
$ git pull
remote: Enumerating objects: 6, done.
remote: Counting objects: 100% (6/6), done.
remote: Compressing objects: 100% (3/3), done.
remote: Total 4 (delta 1), reused 4 (delta 1), pack-reused 0
Unpacking objects: 100% (4/4), 5.83 KiB | 2.92 MiB/s, done.
From github.com:bodymindarts/cf-k8s-cepler
   b68074a..61d0273  master     -> origin/master
Updating b68074a..61d0273
Fast-forward
 .cepler/testflight.state | 566 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
 1 file changed, 566 insertions(+)
 create mode 100644 .cepler/testflight.state
```

This commit should in-turn trigger another run of the workflow. You can go back to https://github.com/your-github-org/cf-k8s-cepler/actions and click on the latest commit `[cepler] Updated testflight state` to watch the next deploy.
This time the `deploy-testflight` job should complete as a no-op. The `deploy-staging` job should complete succesfully creating another commit.

From here on any change to the files referenced in the `cepler.yml` file should trigger successive deploys. Hence we have achieved a continous deployment pipeline that deploys cf-for-k8s to successive environments via github actions.

## Conclusion

To check that things are working as expected you can findout the external ip of the `istio-ingressgateway` and point your dns entry to it:
```
$ kubectl get svc -n istio-system
NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                                                      AGE
istio-ingressgateway   LoadBalancer   192.168.77.107   35.246.241.158   15021:31048/TCP,80:30241/TCP,443:30963/TCP,15443:30925/TCP   23m
istiod                 ClusterIP      192.168.90.225   <none>           15010/TCP,15012/TCP,443/TCP,15014/TCP,853/TCP                23m
```
Then once your DNS has been updated run:
```
$ cf api api.<testflight-dns> --skip-ssl-validation
$ cf auth admin `cat k8s/testflight-values.yml | yq -r .cf_admin_password`
```

