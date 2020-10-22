# Cepler templates

This repository introduces the [cepler-templates](https://github.com/bodymindarts/cepler-templates) project via the example of deploying [cf-for-k8s](https://github.com/cloudfoundry/cf-for-k8s) using `github-actions` as the CD driver.

## Introduction

Deploying software to multiple environments (such as dev / staging / production) introduces operational complexity that requires explicit managing in order to ensure parity between environments.
Previously I wrote an [article](https://github.com/starkandwayne/cepler-demo) introducing how you can use [cepler](https://github.com/bodymindarts/cepler) to significantly reduce this overhead (and it is recommended to read that first).

In this article we will use [cepler-templates](https://github.com/bodymindarts/cepler-templates) to automate the execution of the `cepler check`, `cepler prepare`, `cepler record` cycle to deploy [cf-for-k8s](https://github.com/cloudfoundry/cf-for-k8s) using github actions.

## Prerequisites

If you want to follow along with the demo you will need access to 2 publicly accessible kubernetes clusters representing 2 environments that we want to deploy cf to.

If you want the resulting cf to be fully functional you will also need a dns name you can use to access cf.

## Preparation

First we will clone the [cf-for-k8s](https://github.com/cloudfoundry/cf-for-k8s) repo and generate some values we need.

```
$ git clone https://github.com/cloudfoundry/cf-for-k8s && cd cf-for-k8s
$ git checkout v1.0.0
$ ./hack/generate-values.sh -d <your-dns-endpoint> > cf-values.yml
```

Then we will create a new repository to store the files needed to deploy cf-for-k8s.

- Go to github.com and create a new repository called cf-k8s-cepler.
```
$ cd ..
$ git clone git@github.com:<github-org>/cf-k8s-cepler.git && cd cf-k8s-cepler
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

Now we need to add the values we generated in the previous step and append some dockerhub credentials to it. Don't actually add your password here, that will be injected via the github secrets meachnism.
```
$ cp ../cf-for-k8s/cf-values.yml ./k8s/
cat <<EOF >> k8s/cf-values.yml
app_registry:
  hostname: https://index.docker.io/v1/
  repository_prefix: "<dockerhub_username>"
  username: "<dockerhub_username>"
  password: DUMMY
EOF
$ git add . && git commit -m 'Add cf-values'
```

Next we will add a `cepler.yml` and `ci.yml` which are needed to generate the deployment pipeline.
```
$ cat <<EOF > cepler.yml
environments:
  testflight:
    latest:
    - k8s/**/*
  staging:
    passed: testflight
    propagated:
    - k8s/**/*
    - k8s/cf-values.yml
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
  - k8s/cf-values.yml

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
$ git push -u origin master
```
