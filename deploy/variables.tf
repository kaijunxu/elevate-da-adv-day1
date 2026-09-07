variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "gcp_region" {
  description = "Default Google Cloud deployment region"
  type        = string
  default     = "us-central1"
}

variable "collaborators" {
  description = "A list of collaborator email addresses to grant Project IAM Admin role"
  type        = list(string)
  default     = []
}

variable "enabled_apis" {
  description = "Curated list of essential GCP service domain enablement targets"
  type        = list(string)
  default = [
    "aiplatform.googleapis.com",
    "biglake.googleapis.com",
    "bigquery.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "bigquerydatapolicy.googleapis.com",
    "bigqueryreservation.googleapis.com",
    "bigqueryunified.googleapis.com",
    "bigtable.googleapis.com",
    "bigtableadmin.googleapis.com",
    "cloudaicompanion.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "composer.googleapis.com",
    "compute.googleapis.com",
    "datacatalog.googleapis.com",
    "dataplex.googleapis.com",
    "dataproc.googleapis.com",
    "geminidataanalytics.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "managedkafka.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "workloadidentity.googleapis.com",
  ]
}

variable "data_service_roles" {
  description = "List of IAM roles (without roles/ prefix) to assign to data_service service account"
  type        = list(string)
  default = [
    "biglake.admin",                     # module 1 (Read from federated catalog)
    "bigquery.dataEditor",               # module 1 (Write BQ tables)
    "bigquery.jobUser",                  # module 1 (Run BQ jobs/queries)
    "bigquery.connectionUser",           # module 1 (Read BigLake external tables)
    "bigquery.readSessionUser",          # module 1 (Spark BigQuery Storage Read API)
    "composer.worker",                   # module 1 (Composer environment worker nodes)
    "dataproc.editor",                   # module 1 (Submit Dataproc Serverless batches)
    "dataproc.worker",                   # module 1 (Dataproc Serverless execution)
    "geminidataanalytics.dataAgentUser", # module 3
    "iam.serviceAccountUser",            # module 1 (Composer to act as Dataproc execution SA)
    "logging.logWriter",                 # module 1 & 2 (VM and container logging)
    "managedkafka.client",               # module 2 (Kafka VM client)
    "run.invoker",                       # module 3 (Cloud Run Invoker — for Bigtable MCP)
    "secretmanager.secretAccessor",      # module 3 (Cloud Run Secret Accessor — for Bigtable MCP)
    "storage.objectUser",                # module 1 & 2 (Read/Write GCS data)
  ]
}

# =====================================================================
# VARIABLES FOR RESOURCE IDENTIFIERS REFERENCED ACROSS LAB MODULES
# =====================================================================

# Service Account IDs
variable "cymbal_sa_data_id" {
  type    = string
  default = "cymbal-sa-data"
}

# BigQuery dataset IDs
variable "dataset_id_bronze" {
  type    = string
  default = "cymbal_bronze"
}
variable "dataset_id_silver" {
  type    = string
  default = "cymbal_silver"
}
variable "dataset_id_gold" {
  type    = string
  default = "cymbal_gold"
}

variable "kafka_cluster_id" {
  type    = string
  default = "kafka-cluster"
}

variable "kafka_connect_cluster_id" {
  type    = string
  default = "kafka-connect-cluster"
}

variable "order_anomaly_endpoint_name" {
  description = "Name of the Vertex AI endpoint for order anomaly detection"
  type        = string
  default     = "order-anomaly-endpoint"
}

variable "cashier_abuse_endpoint_name" {
  description = "Name of the Vertex AI endpoint for cashier abuse detection"
  type        = string
  default     = "cashier-abuse-endpoint"
}

