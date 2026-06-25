# Kubernetes resources (StorageClass, Namespaces, cluster-vars ConfigMap) are
# created imperatively via kubectl in the GitHub Actions apply workflow.
# Keeping the kubernetes provider out of this module avoids provider
# initialisation failures during `run-all plan` on an unapplied cluster.
