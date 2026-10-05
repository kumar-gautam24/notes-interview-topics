# Kubernetes, from one container to a running AKS cluster

> A course in 11 lessons. The in-page simulations mentioned below live in the interactive version, [`from-container-to-aks.html`](from-container-to-aks.html) — download it and open it in a browser.

You'll go from "what is a container" to deploying, exposing, scaling and debugging an app on Azure Kubernetes Service. Each lesson builds on the one before, so take them in order the first time.

### How every lesson is built

Good technical teaching follows the same arc each time, so your brain knows where it is. Every lesson here moves through six stages, marked by the same coloured squares:

**The problem** — What breaks without this idea. You learn a tool faster when you feel the pain it removes.

**Picture it** — A real-world analogy to hang the concept on before the jargon arrives.

**How it works** — The actual mechanism, using the terms the official docs use.

**Try it** — YAML, commands, or an in-page simulation you can poke at.

**Check yourself** — Short questions. Answering from memory is what makes it stick, so guess before you look.

**Where people slip** — The mistakes that show up in real clusters and interviews.

### What you need

- For lessons 1 to 8: nothing. The simulations run in this page. If you want a real cluster on your laptop, install Docker Desktop plus `kind` or `minikube`, and `kubectl`.
- For lessons 9 and 10: an Azure account and the Azure CLI (`az`). A small two-node cluster costs real money per hour, so the lab ends with a cleanup command.

Sources this follows: the Kubernetes concepts docs (kubernetes.io/docs/concepts) and Microsoft's AKS core concepts pages. Links are in each lesson.

Lesson 1 · Basic

## Containers: shipping software in a standard box

### The problem

Your API runs fine on your laptop with Python 3.12 and a specific version of FastAPI. The server has Python 3.9 and an older OpenSSL. It crashes. A teammate's machine has a third set of versions. "Works on my machine" is the oldest bug in deployment, and it's caused by the app depending on whatever happens to be installed around it.

### Picture it

Before shipping containers, dock workers loaded sacks, barrels and crates by hand, each differently. The steel shipping container changed that: one standard box, and every crane, ship and truck in the world knows how to move it without caring what's inside. A software container does the same for your app. Your code and everything it needs go inside the box; any machine with a container runtime can run it.

### How it works

An **image** is a read-only template: your code, the language runtime, libraries and a start command, stacked as layers. You build it from a **Dockerfile**. A **container** is a running instance of an image. One image can run as fifty containers.

A container is not a small virtual machine. It's an ordinary Linux process that the kernel isolates using **namespaces** (it sees its own filesystem, network and process list) and limits using **cgroups** (it gets a fixed share of CPU and memory). All containers on a host share that host's kernel. That's why they start in seconds and weigh megabytes, while a VM boots a whole guest operating system.

|  | Virtual machine | Container |
| --- | --- | --- |
| Isolation | Full guest OS on a hypervisor | Process isolated by the host kernel |
| Size | Gigabytes | Megabytes to a few hundred MB |
| Start time | Tens of seconds to minutes | Under a second to a few seconds |
| Kernel | Its own | Shared with the host |

Images live in a **registry**: Docker Hub publicly, or Azure Container Registry (ACR) privately when you're on Azure. An image name like `myacr.azurecr.io/hello-api:1.0` reads as registry / repository : tag.

### Try it

A minimal API we'll carry through the whole course.

main.py

```
from fastapi import FastAPI
import socket

app = FastAPI()

@app.get("/")
def hello():
    # hostname = the pod name once this runs in Kubernetes
    return {"msg": "hello", "served_by": socket.gethostname()}

@app.get("/healthz")
def health():
    return {"ok": True}
```

Dockerfile

```
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn
COPY main.py .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Build and run

```
docker build -t hello-api:1.0 .
docker run -d -p 8080:8000 --name hello hello-api:1.0
curl localhost:8080          # {"msg":"hello","served_by":"3f2a9c..."}
docker ps                    # see it running
docker rm -f hello           # stop and remove
```

`-p 8080:8000` maps port 8080 on your laptop to port 8000 inside the container. Keep that "outside port : inside port" idea in mind; Kubernetes Services use the same pattern.

### Check yourself

You run the same image three times. What do you have?

The image is the template; each `docker run` creates a separate running container from it.

What do all containers on one host share?

Namespaces give each container its own filesystem view and network, but they all run on the same kernel. That shared kernel is the main difference from VMs.

### Where people slip

**Deploying with the `:latest` tag** — You can't tell which version is running or roll back cleanly. Tag every build with a version or git SHA.

**Writing important data inside the container** — A container's filesystem disappears when it's replaced. Data that must survive goes in a volume or a database.

**Binding the server to 127.0.0.1** — Inside a container, localhost means only the container itself. Servers must listen on 0.0.0.0 to be reachable.

Lesson 2 · Basic

## Why you need an orchestrator

### The problem

One container on one server is easy. Now you have 40 containers across 6 servers. At 3 a.m. one server dies and takes 7 containers with it. On Friday a sale triples traffic. On Monday you need to ship version 1.1 without dropping requests. Each of these used to mean someone running scripts by hand.

### Picture it

"Kubernetes" is Greek for helmsman, the person steering the ship. A better everyday picture is a thermostat. You don't tell it "turn the heater on for 12 minutes". You say "I want 24°C", and it keeps measuring and correcting forever. Kubernetes works the same way: you declare the state you want, and it keeps nudging reality toward it.

### How it works

You describe the **desired state** in YAML: "run 3 copies of `hello-api:1.0`, each with half a CPU, reachable at the name `hello-api`". You submit it to the cluster's API. From then on, components called **controllers** run a loop:

Observe actual state→Compare with desired→Act to close the gap↺

This is called **reconciliation**, and it is the single most important idea in Kubernetes. Almost every feature is a controller reconciling something. It gives you: scheduling containers onto machines with room, restarting or replacing failed ones (self-healing), scaling up and down, stable networking between services, rolling updates and rollbacks, and managed configuration and secrets.

**Declarative vs imperative.** `kubectl run` or `kubectl scale` are imperative: do this now. `kubectl apply -f app.yaml` is declarative: make it look like this file. Real teams use declarative files kept in git, because the file becomes the record of what should be running.

### Check yourself

A node with 2 of your 3 app copies crashes. Your YAML said 3 replicas. What does Kubernetes do?

The controller sees actual (1) ≠ desired (3) and closes the gap by itself. Kubernetes doesn't repair machines; it reschedules work away from them.

Does Kubernetes build your container images?

Building happens in Docker or your CI pipeline. Kubernetes only pulls and runs finished images.

### Where people slip

**Fixing things with one-off commands** — If you `kubectl edit` live and never update the YAML, the next `apply` silently undoes your fix.

**Using Kubernetes for one small app** — It has real operational weight. A single API with modest traffic is often better on a PaaS like Azure App Service or Container Apps.

Lesson 3 · Basic

## Inside a cluster: the control plane and the nodes

### The problem

"I ran `kubectl apply` and my pods are stuck in Pending." To debug that, you need to know which part of the cluster was supposed to act and didn't. Without a mental map, Kubernetes feels like a black box that sometimes works.

### Picture it

A port. The **harbour office** (control plane) holds the ledger of every shipment, decides which dock each container goes to, and dispatches crews. The **docks** (worker nodes) are where containers are actually unloaded and handled, each with a dock foreman who takes orders from the office.

### How it works

A **cluster** is a set of machines split into two roles.

#### Control plane: the brain

- **kube-apiserver** is the front door. Every request (from `kubectl`, from other components) goes through it. It's the only component that talks to etcd.
- **etcd** is a consistent key-value store holding the whole cluster state. If it's lost without a backup, the cluster forgets everything.
- **kube-scheduler** watches for pods with no node assigned and picks a node for each, based on requested CPU/memory and constraints.
- **kube-controller-manager** runs the built-in controllers (Deployment, ReplicaSet, Node and more) that do the reconciling.
- **cloud-controller-manager** talks to the cloud: it creates load balancers, attaches disks, and notices deleted VMs.

#### Worker nodes: the muscle

- **kubelet** is the agent on every node. It watches the API for pods assigned to its node and makes sure their containers are running and healthy.
- **container runtime** (usually **containerd**) pulls images and starts containers.
- **kube-proxy** programs network rules on the node so traffic sent to a Service reaches the right pods. Some networking setups (like Cilium) replace it.

One rule simplifies everything: **components don't call each other directly**. They all watch the API server and write back to it. The scheduler never phones the kubelet; it writes "pod X → node 2" into the API, and node 2's kubelet notices.

### Try it: trace a `kubectl apply`

Step through what happens when you apply a Deployment with 3 replicas.

Your laptop

kubectl

Control plane

kube-apiserveretcdkube-schedulercontroller-managercloud-controller-manager

Node 1

kubeletcontainerdkube-proxypodpod

Node 2

kubeletcontainerdkube-proxypod

Look at a real cluster's parts

```
kubectl get nodes -o wide              # the machines
kubectl get pods -n kube-system        # system components running as pods
kubectl cluster-info                   # where the API server lives
```

### Check yourself

Which component decides which node a new pod runs on?

The scheduler only assigns. The kubelet on that node then does the actual starting.

Pods stay Pending forever and `kubectl describe pod` shows no node assigned. Which part do you suspect first?

No node assigned means the scheduler couldn't place it. An image pull failure happens later, after assignment, and shows as ImagePullBackOff.

### Where people slip

**Thinking the control plane runs your app** — Your pods run on worker nodes. The control plane only decides and records.

**Mixing up kubelet and kubectl** — kubectl is your client tool. kubelet is the agent on each node. They never talk directly.

Docs: kubernetes.io/docs/concepts/overview/components

Lesson 4 · Basic

## Pods: the smallest thing Kubernetes runs

### The problem

Sometimes two processes belong together: your API and a small helper that ships its logs, or refreshes a certificate it reads. They need to share files and talk over localhost, and they should always be placed on the same machine and live and die together. Scheduling single containers can't express that.

### Picture it

A pod is a flat shared by roommates. They share one street address (the pod's IP), one kitchen (shared volumes), and can shout to each other across the hall (localhost). When the lease ends, everyone moves out together, and the next flat has a different address.

### How it works

- A **pod** wraps one or more containers. Most pods have exactly one; the extra-helper pattern is called a **sidecar**.
- Each pod gets **its own IP**. Containers in the same pod share it and reach each other on `localhost`.
- Pods are **ephemeral**. When one dies, it isn't revived; a new pod with a new name and a new IP replaces it. That fact drives the next two lessons.
- Status moves through phases: `Pending` → `Running` → `Succeeded` or `Failed`. Inside, a container that keeps crashing shows `CrashLoopBackOff`, meaning kubelet is restarting it with growing delays.

### Try it

pod.yaml

```
apiVersion: v1
kind: Pod
metadata:
  name: hello-pod
  labels:
    app: hello-api      # labels matter a lot from lesson 5 on
spec:
  containers:
  - name: api
    image: hello-api:1.0
    ports:
    - containerPort: 8000
```

The commands you'll use every day

```
kubectl apply -f pod.yaml
kubectl get pods -o wide              # status, IP, node
kubectl describe pod hello-pod        # events: scheduling, pulling, errors
kubectl logs hello-pod                # stdout of the container
kubectl exec -it hello-pod -- sh      # shell inside it
kubectl port-forward pod/hello-pod 8080:8000   # reach it from laptop
kubectl delete pod hello-pod          # gone for good, nothing replaces it
```

Every Kubernetes object has the same four top-level fields: `apiVersion`, `kind`, `metadata` (name, labels) and `spec` (what you want). Once you see that, every YAML file reads the same way.

### Check yourself

Two containers in the same pod. How does container A call container B on port 9000?

They share one network namespace, so it's just localhost. That's also why two containers in a pod can't listen on the same port.

You delete a bare pod (created from pod.yaml). What happens?

A bare pod has no controller watching it. That's why you almost never create pods directly; lesson 5 fixes this.

### Where people slip

**Hardcoding pod IPs** — They change on every replacement. Use a Service name instead (lesson 6).

**One pod per app tier, all in one** — Putting frontend, API and database in one pod means they can't scale separately. One pod = one tightly coupled unit.

Lesson 5 · Basic → Intermediate

## Deployments: keep N copies alive, update without downtime

### The problem

From lesson 4: a dead pod stays dead. You want 3 copies running always, a way to change that to 10 during a sale, and a way to roll out version 1.1 a few pods at a time, with an undo button.

### Picture it

A restaurant manager whose only rule is "3 cooks on shift". A cook walks out, a new one is called in. Switch to the new menu? The manager swaps cooks one at a time, so the kitchen never stops serving.

### How it works

Deploymentmanages →ReplicaSetkeeps N →Pods

- A **ReplicaSet** keeps exactly N pods matching a **label selector** alive. That's the self-healing.
- A **Deployment** manages ReplicaSets. When you change the pod template (say, the image tag), it creates a new ReplicaSet and shifts pods from old to new: a **rolling update**. `maxSurge` (extra pods allowed during rollout) and `maxUnavailable` (pods allowed to be down) control the pace.
- The old ReplicaSet is kept at 0 replicas, which is how `kubectl rollout undo` works.
- **Labels** are key-value tags on objects. **Selectors** are queries over labels. The ReplicaSet doesn't track pods by name; it counts "pods with `app=hello-api`". Services use the same trick.

### Try it: break pods and watch them come back

replicas: **3**

Delete a pod and the ReplicaSet controller sees 2 ≠ 3 and creates a replacement with a new name and IP. Drag the slider and it adds or removes pods to match. That's reconciliation, live.

deployment.yaml

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-api        # must match template labels below
  strategy:
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  template:                   # the pod blueprint
    metadata:
      labels:
        app: hello-api
    spec:
      containers:
      - name: api
        image: hello-api:1.0
        ports: [{ containerPort: 8000 }]
        resources:
          requests: { cpu: 100m, memory: 128Mi }   # scheduler uses this
          limits:   { memory: 256Mi }             # OOM-killed above this
        readinessProbe:         # only send traffic when this passes
          httpGet: { path: /healthz, port: 8000 }
        livenessProbe:          # restart container if this fails
          httpGet: { path: /healthz, port: 8000 }
          initialDelaySeconds: 10
```

Scale, update, roll back

```
kubectl apply -f deployment.yaml
kubectl get deploy,rs,pods -l app=hello-api
kubectl scale deployment hello-api --replicas=5
kubectl set image deployment/hello-api api=hello-api:1.1
kubectl rollout status deployment/hello-api
kubectl rollout history deployment/hello-api
kubectl rollout undo deployment/hello-api
```

### Check yourself

You change the image from 1.0 to 1.1 and apply. What gets created?

Pods are never patched in place for an image change. The Deployment rolls a new ReplicaSet up and the old one down.

What's the difference between a readiness and a liveness probe?

Readiness = "can I take requests right now?" Liveness = "am I stuck and need a restart?" Making liveness too aggressive causes restart loops during slow startups.

### Where people slip

**Selector and template labels don't match** — The API rejects the Deployment. Copy the labels exactly.

**No resource requests** — The scheduler then packs pods blindly, nodes get overloaded, and pods get evicted under pressure.

**No readiness probe** — New pods get traffic before the app has finished starting, so every rollout causes a burst of errors.

Lesson 6 · Intermediate

## Services and ClusterIP: one stable address for moving pods

### The problem

Your frontend pods need to call the `hello-api` pods. But there are 3 of them, their IPs change every time one is replaced, and during a rollout the set changes every few seconds. What address does the frontend use?

### Picture it

A company's support phone number. Agents join, leave and change desks every day, but the number on the website never changes. Call it, and the switchboard connects you to whichever agent is free right now. A Service is that number; the pods are the agents.

### How it works

- A **Service** gives a set of pods a stable virtual IP and a DNS name. It finds its pods with a **label selector**, exactly like a ReplicaSet.
- **ClusterIP** is the default type. The IP comes from a separate service address range and is reachable **only from inside the cluster**. It's how microservices, internal APIs and databases talk to each other.
- Kubernetes keeps **EndpointSlices**: the live list of IPs of pods that match the selector *and are Ready*. A pod failing its readiness probe drops out of this list.
- **kube-proxy** on every node turns that list into routing rules, so a packet sent to `ClusterIP:port` is redirected to one of the pod IPs on `targetPort`. Nothing actually "listens" on the ClusterIP; it's a rule, not a server. (In iptables mode the pod is picked at random.)
- **CoreDNS** gives each Service a name: `hello-api` from the same namespace, or `hello-api.default.svc.cluster.local` in full.

frontend pod→hello-api:80 (ClusterIP)→ kube-proxy rules →one Ready pod :8000

**port vs targetPort:** `port` is what callers use on the Service (80). `targetPort` is where the container actually listens (8000). Same idea as `docker run -p 8080:8000`.

### Try it: what does the Service send traffic to?

Toggle each pod's label and readiness, then send requests. Only pods that match the selector and are Ready are endpoints.

Service `hello-api` · selector `app=hello-api`

service.yaml

```
apiVersion: v1
kind: Service
metadata:
  name: hello-api
spec:
  type: ClusterIP          # default; you can omit this line
  selector:
    app: hello-api       # matches the Deployment's pod labels
  ports:
  - port: 80              # what callers use
    targetPort: 8000      # where the container listens
```

Test it from inside the cluster

```
kubectl apply -f service.yaml
kubectl get svc hello-api                 # note CLUSTER-IP, EXTERNAL-IP is <none>
kubectl get endpointslices -l kubernetes.io/service-name=hello-api
# throwaway pod to act as a client; run it a few times and watch served_by change
kubectl run tmp --rm -it --image=busybox --restart=Never -- wget -qO- http://hello-api
# from your laptop, for testing only
kubectl port-forward svc/hello-api 8080:80
```

### Check yourself

Your Service exists but every request fails, and its EndpointSlice is empty. Most likely cause?

This is the most common Service bug. Compare `kubectl get svc hello-api -o yaml` selector with `kubectl get pods --show-labels`.

Can you `curl` a ClusterIP from your laptop?

ClusterIP rules exist only on cluster nodes. For outside access, see the next lesson.

Callers use port 80, the container listens on 8000. Which field is 8000?

`port` is the Service's port; `targetPort` is the container's.

### Where people slip

**A label typo** — `app: hello-api` vs `app: helloapi` gives a Service with zero endpoints and no error message.

**Wrong targetPort** — Endpoints look fine, but connections are refused because nothing listens on that port in the container.

**Calling across namespaces with the short name** — `hello-api` only resolves in the same namespace. Use `hello-api.other-ns` otherwise.

Docs: kubernetes.io/docs/concepts/services-networking/service/

Lesson 7 · Intermediate

## Getting traffic in from outside

### The problem

ClusterIP is perfect between services, but your mobile app's users are on the internet. They need a public address that reaches your pods, ideally with one address serving several APIs.

### Picture it

An office building. **ClusterIP** is the internal extension; only people inside can dial it. **NodePort** is a side door on every floor with the same door number. **LoadBalancer** is a staffed main entrance on the street that spreads visitors across those doors. **Ingress** is the receptionist at that entrance who reads your appointment and sends you to the right department.

### How it works

The types are **layered**, each built on the previous one:

- **NodePort** creates a ClusterIP, then also opens the same port (default range 30000–32767) on every node. Traffic to any `NodeIP:nodePort` reaches the Service, even if that node runs none of its pods. Fine for testing; awkward for production.
- **LoadBalancer** creates a NodePort and a ClusterIP, then asks the cloud-controller-manager to provision a real cloud load balancer with an external IP. On AKS that's an Azure Load Balancer with a public IP. While it's being provisioned, `EXTERNAL-IP` shows `<pending>`.
- **Ingress** isn't a Service type. It's a set of HTTP routing rules (host and path → Service), served by an **ingress controller** that you install, which itself sits behind one LoadBalancer. The newer **Gateway API** does the same job with a richer model.
- **ExternalName** is the odd one: a DNS alias to something outside the cluster, no proxying.

### Try it: follow the traffic path

```

```

| Type | Reachable from | Typical use | Cost on AKS |
| --- | --- | --- | --- |
| ClusterIP | Inside the cluster | Service-to-service, databases | Free |
| NodePort | Anyone who can reach a node IP | Testing, custom external LB | Free, but nodes usually have no public IP |
| LoadBalancer | Internet (or VNet if internal) | One public TCP/HTTP entry | A public IP and LB rules per Service |
| Ingress | Internet via one LB | Many HTTP APIs, TLS, path routing | One LB shared by all routes |

### Check yourself

You create a LoadBalancer Service. How many Service-level things exist?

The layers stack: the cloud LB forwards to node ports, which forward to the ClusterIP rules, which pick a pod.

You have 12 HTTP microservices to expose publicly. Best approach?

One entry point, path or host routing, TLS in one place, and one public IP to pay for and secure.

### Where people slip

**Exposing a database with LoadBalancer** — It puts your database on the public internet. Keep it ClusterIP; use port-forward to reach it yourself.

**EXTERNAL-IP stuck on pending in a local cluster** — kind and minikube have no cloud controller. Use `minikube tunnel` or port-forward locally; on AKS it resolves in a minute or two.

Lesson 8 · Intermediate

## Configuration, secrets and namespaces

### The problem

The same image should run in dev and prod with different database URLs and API keys. Baking those into the image means one image per environment and secrets in your registry. And with several teams on one cluster, everything ends up in one crowded list.

### Picture it

Your Flutter app reads `--dart-define` values or a .env file at build time so the same code can point at staging or production. Kubernetes does the same, but at *run* time: the image stays identical; the settings are handed in when the pod starts.

### How it works

- **ConfigMap**: non-secret key-value settings, injected as environment variables or mounted as files.
- **Secret**: same shape, for passwords and keys. By default values are only **base64-encoded**, not encrypted, so access control matters. On AKS, the usual production pattern is Azure Key Vault mounted through the Secrets Store CSI driver.
- **Namespace**: a named folder inside the cluster (`dev`, `team-payments`). Names only need to be unique within a namespace, and you can attach access rules and resource quotas per namespace. `kube-system` holds cluster components; don't put apps there.

### Try it

```
kubectl create namespace dev
kubectl -n dev create configmap api-config --from-literal=LOG_LEVEL=debug
kubectl -n dev create secret generic api-secrets --from-literal=DB_PASSWORD='s3cret'
kubectl -n dev get secret api-secrets -o yaml   # see: just base64
```

Using them in the Deployment's container spec

```
        envFrom:
        - configMapRef: { name: api-config }
        - secretRef:    { name: api-secrets }
```

Changing a ConfigMap doesn't restart pods that read it as environment variables. Run `kubectl rollout restart deployment/hello-api` to pick up new values.

### Check yourself

Is a Kubernetes Secret encrypted by default?

Anyone who can read Secrets in that namespace can decode them in one command. Treat RBAC on Secrets as the real lock.

### Where people slip

**Committing secret YAML to git** — Base64 isn't hiding anything. Use Key Vault, sealed secrets, or create them from CI.

**Forgetting `-n`** — "My pods vanished" usually means you're looking in the default namespace.

Lesson 9 · Intermediate → Good

## AKS: what Azure runs for you, and what you still own

### The problem

Running the control plane yourself means keeping etcd backed up and highly available, patching the API server, rotating certificates, and upgrading every component in the right order. It's a full-time job that doesn't ship any features.

### Picture it

Renting a fully serviced office vs building one. With AKS, Azure runs the building (power, security desk, lifts: the control plane). You still choose how many desks to rent, who sits where and what work happens there (nodes, workloads, access).

### How it works

#### Who manages what

| Azure manages | You manage |
| --- | --- |
| Control plane: kube-apiserver, etcd, scheduler, controller-manager, cloud-controller-manager. You can't log into it; you reach it through the API. | Your workloads: Deployments, Services, config, probes, resource requests. |
| Control plane availability and patching; upgrades are triggered through `az` or the portal. | Choosing node VM sizes, node counts, autoscaling, and when to upgrade. |
| Node OS images (you apply updates or enable auto-upgrade). | Access control, network policies, cost. |

Billing follows that split: you pay for the node VMs (and disks, load balancers, IPs). The control plane is free on the Free tier; paid tiers add an uptime SLA.

#### Concepts specific to AKS

- **Nodes are Azure VMs**, grouped into **node pools** (VM Scale Sets) that share a VM size and OS. A **system node pool** runs critical add-ons like CoreDNS; **user node pools** run your apps. You can add a GPU pool for ML work alongside a cheap general pool.
- **Cluster autoscaler** adds nodes when pods can't be scheduled and removes idle ones. The **Horizontal Pod Autoscaler** adds pods based on CPU or other metrics. They work together: more pods → no room → more nodes.
- **AKS Automatic vs Standard.** Automatic presets node management, scaling and many production defaults. Standard gives you full control over node pools, networking and scaling.
- **Networking plugin** (Azure CNI, commonly in Overlay mode) decides how pod IPs relate to your Azure virtual network. It matters when pods must talk to other Azure resources by private IP.

#### How Kubernetes objects map to Azure resources

| You create | Azure creates |
| --- | --- |
| Service `type: LoadBalancer` | A rule and public IP on the cluster's Azure Load Balancer |
| PersistentVolumeClaim | An Azure Disk or Azure Files share |
| Image reference `myacr.azurecr.io/...` | Pull from Azure Container Registry, authorised by attaching ACR to the cluster |
| Node pool | A VM Scale Set in a separate "node resource group" (MC\_...) |
| Login with `kubectl` | Optionally Microsoft Entra ID identities with Kubernetes or Azure RBAC |

### Try it: create a small cluster

```
az login
az group create --name rg-k8s-learn --location centralindia
az acr create --resource-group rg-k8s-learn --name <uniqueacrname> --sku Basic
az aks create \
  --resource-group rg-k8s-learn \
  --name aks-learn \
  --node-count 2 \
  --attach-acr <uniqueacrname> \
  --generate-ssh-keys
az aks get-credentials --resource-group rg-k8s-learn --name aks-learn
kubectl get nodes                    # two Azure VMs, Ready
az aks nodepool list --resource-group rg-k8s-learn --cluster-name aks-learn -o table
```

`get-credentials` writes the cluster's address and your credentials into `~/.kube/config`. From that point, every `kubectl` command from lessons 4 to 8 works unchanged against AKS. That portability is the point.

### Check yourself

In AKS, can you SSH into the etcd server to take a backup?

Azure runs and protects the control plane. Backups of your workloads are done at the Kubernetes level (for example, with a backup tool or by keeping manifests in git).

Pods are Pending because nodes are full, and cluster autoscaler is enabled. What happens?

Cluster autoscaler reacts to unschedulable pods by growing the node pool within its min/max limits.

### Where people slip

**Forgetting to delete the learning cluster** — Two VMs running all month is a real bill. `az group delete --name rg-k8s-learn --yes --no-wait` removes everything in one go.

**Running apps on the system pool** — A noisy app can starve CoreDNS and break the whole cluster's name resolution. Add a user pool.

**Editing resources in the MC\_ resource group by hand** — AKS manages those. Change things through `az aks` or Kubernetes, or they'll be reverted or break upgrades.

Docs: learn.microsoft.com/azure/aks/core-aks-concepts and /concepts-clusters-workloads

Lesson 10 · Good

## Lab: ship hello-api to AKS, end to end

### The problem

Knowing each piece isn't the same as wiring them together. This lab connects lessons 1 to 9 in the order you'd do it at work. Run it locally first (kind or minikube) if you want to avoid Azure costs; only steps 2 and 7 change.

### Picture it

Dockerfile→image in ACR→Deployment (3 pods)→ClusterIP Service→LoadBalancer / Ingress→your phone

### Steps

#### 1. Build the image

```
docker build -t hello-api:1.0 .
```

#### 2. Push to ACR

```
az acr login --name <uniqueacrname>
docker tag hello-api:1.0 <uniqueacrname>.azurecr.io/hello-api:1.0
docker push <uniqueacrname>.azurecr.io/hello-api:1.0
# Apple Silicon Mac? build for the nodes' CPU: docker build --platform linux/amd64 ...
# local kind instead: kind load docker-image hello-api:1.0
```

#### 3. Deploy

Use `deployment.yaml` from lesson 5 with the image changed to `<uniqueacrname>.azurecr.io/hello-api:1.0`, and `service.yaml` from lesson 6.

```
kubectl apply -f deployment.yaml -f service.yaml
kubectl get pods -l app=hello-api -w        # wait for 3/3 Running, Ctrl+C
```

#### 4. Prove ClusterIP load-spreading

```
kubectl run tmp --rm -it --image=busybox --restart=Never -- \
  sh -c 'for i in 1 2 3 4 5 6; do wget -qO- http://hello-api; echo; done'
# served_by shows different pod names
```

#### 5. Break it on purpose

```
kubectl delete pod -l app=hello-api --wait=false
kubectl get pods -l app=hello-api -w        # watch 3 new pods appear
```

#### 6. Roll out v1.1 and roll back

```
# change the msg in main.py, then build, tag and push as :1.1
kubectl set image deployment/hello-api api=<uniqueacrname>.azurecr.io/hello-api:1.1
kubectl rollout status deployment/hello-api
kubectl rollout undo deployment/hello-api
```

#### 7. Expose publicly

```
kubectl patch svc hello-api -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc hello-api -w                # EXTERNAL-IP goes from <pending> to an IP
curl http://<EXTERNAL-IP>/
```

#### 8. Autoscale

```
kubectl autoscale deployment hello-api --cpu-percent=60 --min=3 --max=10
kubectl get hpa
```

#### 9. Clean up

```
az group delete --name rg-k8s-learn --yes --no-wait
```

### Check yourself

Pods show `ImagePullBackOff` right after step 3 on AKS. First two things to check?

`kubectl describe pod` shows the pull error. It's almost always a typo, a tag you didn't push, or missing registry permission (`az aks update --attach-acr`).

### Where people slip

**Pushing an arm64 image from an M-series Mac** — AKS nodes are usually amd64; the pod fails with "exec format error". Build with `--platform linux/amd64`.

**Patching the Service type and forgetting the YAML** — Update `service.yaml` too, or the next apply reverts it to ClusterIP.

Lesson 11 · Good

## Debugging playbook, and a final check

### The problem

In real work and interviews, the skill that separates "has read about Kubernetes" from "can run it" is calm, ordered debugging. Every status message points at a specific part of the system you now know.

### Picture it

Follow the request's journey and ask, at each hop, "did this step happen?": was the pod scheduled, did the image pull, did the process start, is it Ready, does the Service see it, does outside traffic reach the Service. The first "no" is your bug.

### Symptom → cause → command

| You see | It usually means | Look with |
| --- | --- | --- |
| `Pending` | Scheduler can't place it: not enough requested CPU/memory free, node selector or taint mismatch, unbound volume | `kubectl describe pod` → Events |
| `ImagePullBackOff` | Wrong image/tag, or no permission to the registry | `describe pod`; check ACR attach |
| `CrashLoopBackOff` | The app starts and exits: bad config, missing env var, crash on boot, failing liveness probe | `kubectl logs <pod> --previous` |
| `OOMKilled` | Exceeded memory limit | `describe pod` → Last State; raise limit or fix leak |
| `Running` but `0/1 READY` | Readiness probe failing: wrong path/port, app not listening yet | `describe pod` → probe events |
| Service returns nothing | No endpoints (label mismatch, nothing Ready) or wrong targetPort | `kubectl get endpointslices`, `--show-labels` |
| `EXTERNAL-IP <pending>` | No cloud controller (local cluster), or Azure still provisioning / quota | `kubectl describe svc` → Events |

The order to run things in

```
kubectl get pods -o wide                  # 1. what state, which node
kubectl describe pod <pod>                # 2. events at the bottom tell the story
kubectl logs <pod> [--previous]           # 3. what the app said before dying
kubectl get endpointslices                # 4. does the Service see Ready pods
kubectl get events --sort-by=.lastTimestamp   # 5. cluster-wide timeline
```

### Final check: mixed questions

A pod is in CrashLoopBackOff. `kubectl logs` is empty. What next?

The current container may have just restarted and logged nothing yet; `--previous` shows why the last one died.

Which is true about a LoadBalancer Service on AKS?

The layered model from lesson 7.

Which component writes cluster state to etcd?

Only the API server touches etcd. Everything else reads and writes through it.

A pod is Running but missing from the Service's endpoints. Labels match. Why?

EndpointSlices only list Ready pods as serving. Fix the probe or the app's startup.

What do you pay Azure for in an AKS Free-tier cluster?

The managed control plane is free on the Free tier; nodes and networking resources are billed.

### Where to go next

- **StatefulSets and PersistentVolumes** for databases and anything with stable identity or storage.
- **Ingress controllers / Gateway API** with TLS via cert-manager.
- **Helm** for packaging, then **GitOps** (Flux or Argo CD) so git drives the cluster.
- **RBAC and NetworkPolicies** to control who can do what, and which pods can talk.
- Practice: the official interactive tutorials at kubernetes.io/docs/tutorials, and Microsoft Learn's AKS modules. If you aim for certification, CKAD fits a developer path.