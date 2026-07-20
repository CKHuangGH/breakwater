from enoslib.api import generate_inventory, run_ansible
import enoslib as en
import time

en.set_config(ansible_forks=100)

name = "member_cluster-2_nantes"

clusters = "ecotype"

site = "nantes"

cp_nodes = []

all_vm_nodes = []

duration = "3:00:00"

prod_network = en.G5kNetworkConf(type="prod", roles=["my_network"], site=site)

name_job = name + clusters

conf = (
    en.G5kConf.from_settings(job_type="allow_classic_ssh", job_name=name_job, walltime=duration)
    .add_network_conf(prod_network)
    .add_network(
        id="not_linked_to_any_machine", type="slash_22", roles=["my_subnet"], site=site
    )
    .add_machine(
    roles=["role0"], cluster=clusters, nodes=1, primary_network=prod_network
    ).finalize()
)

provider = en.G5k(conf)
provider.destroy()