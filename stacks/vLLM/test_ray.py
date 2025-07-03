# You can run this code outside of the Ray cluster!
import ray

# Starting the Ray client. This connects to a remote Ray cluster.
ray.init("ray://localhost:10001")

# Normal Ray code follows
@ray.remote(num_cpus=0.25)
def do_work(x):
    return x ** x

futures = do_work.remote(2)
print(ray.get(futures))
#....