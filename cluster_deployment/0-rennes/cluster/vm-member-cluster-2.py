from enoslib.api import generate_inventory, run_ansible
import enoslib as en
import time

en.set_config(ansible_forks=100)

name = "member_cluster-2_rennes"

clusters = "paradoxe"

site = "rennes"

cp_nodes = []

all_vm_nodes = []

duration = "03:00:00"

prod_network = en.G5kNetworkConf(type="prod", roles=["my_network"], site=site)

name_job = name + clusters

conf = (
    en.G5kConf.from_settings(job_type=[], job_name=name_job, walltime=duration)
    .add_network_conf(prod_network)
    .add_network(
        id="not_linked_to_any_machine", type="slash_22", roles=["my_subnet"], site=site
    )
    .add_machine(
    roles=["role0"], cluster=clusters, nodes=1, primary_network=prod_network
    ).finalize()
)

provider = en.G5k(conf)
roles, networks = provider.init()
roles = en.sync_info(roles, networks)

subnet = networks["my_subnet"]

cp = 1
w1 = 1

for i in range(0,2):
    start = i * (cp + w1)
    virt_conf = (
        en.VMonG5kConf.from_settings(image="/home/chuang/images/debian13-k8s-large.qcow2")
        .add_machine(
            roles=["cp"],
            number=cp,
            undercloud=roles["role0"],
            flavour_desc={"core": 4, "mem": 8192},
            macs=list(subnet[0].free_macs)[start:start+cp],
        )
        .add_machine(
            roles=["member"],
            number=w1,
            undercloud=roles["role0"],
            flavour_desc={"core": 4, "mem": 8192},
            macs=list(subnet[0].free_macs)[start+cp:start+cp+w1],
        ).finalize()
    )

    vmroles = en.start_virtualmachines(virt_conf,force_deploy=True)

    tempname=name_job+str(i)

    inventory_file = "kubefed_inventory_cluster"+ str(tempname) +".ini" 

    inventory = generate_inventory(vmroles, networks, inventory_file)

    cp_nodes.append(vmroles["cp"][0].address)

    all_vm_nodes.append(vmroles["cp"][0].address)

    for vm in vmroles["member"]:
        all_vm_nodes.append(vm.address)

    time.sleep(45)

    run_ansible(["afterbuild.yml"], inventory_path=inventory_file)

with open("cp_node_list", "a") as f:
    for ip in cp_nodes:
        f.write(ip + "\n")

with open("all_node_list", "a") as f:
    for ip in all_vm_nodes:
        f.write(ip + "\n")