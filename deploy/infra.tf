/**
 * Advanced DA Enablement Workshop — 
 * Learner Landing Zone Bootstrap (module_0/starter/infra.tf)
 *
 * Automates creation of VPC/subnets, service accounts with required 
 * AI & Data IAM permissions, and all resources that need to be pre-
 * provisioned BEFORE hands-on sessions.
 */

# =====================================================================
# SHARED AND COMMON RESOURCES
# =====================================================================

# Enabling service APIs
resource "google_project_service" "workshop_apis" {
  for_each = toset(var.enabled_apis)
  project  = var.project_id
  service  = each.key

  disable_on_destroy = false
}

# BigQuery BigLake Cloud Resource Connection
resource "google_bigquery_connection" "biglake_connection" {
  connection_id = "biglake-iceberg-connection"
  location      = var.gcp_region
  project       = var.project_id
  cloud_resource {}

  depends_on = [
    google_project_service.workshop_apis
  ]
}

# Wait for 60 seconds for the service account of the BigQuery connection to be fully created/propagated
resource "time_sleep" "wait_60_seconds" {
  depends_on = [google_bigquery_connection.biglake_connection]

  create_duration = "60s"
}

# Grant BigQuery connection access to all GCS buckets in the project
resource "google_project_iam_member" "biglake_connection_gcs_access" {
  for_each = toset([
    "roles/storage.objectUser",
    "roles/storage.bucketViewer",
    "roles/aiplatform.user"
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_bigquery_connection.biglake_connection.cloud_resource[0].service_account_id}"

  depends_on = [
    time_sleep.wait_60_seconds
  ]
}

# Project number for service agent IAM permissions
data "google_project" "project" {
  project_id = var.project_id
}

# Dedicated workshop service account & IAM roles
resource "google_service_account" "cymbal_sa_data" {
  account_id   = var.cymbal_sa_data_id
  display_name = "Cymbal Retail Data Service Account"
  project      = var.project_id
  depends_on   = [google_project_service.workshop_apis]
}

resource "google_project_iam_member" "cymbal_sa_data_iam_roles" {
  for_each = toset(var.data_service_roles)
  project  = var.project_id
  role     = "roles/${each.key}"
  member   = "serviceAccount:${google_service_account.cymbal_sa_data.email}"

  depends_on = [
    google_service_account.cymbal_sa_data
  ]
}

# VPC network
resource "google_compute_network" "cymbal_retail_vpc" {
  name                    = "cymbal-retail-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  depends_on              = [google_project_service.workshop_apis]
}

# VPC subnet (/22 required for Managed Kafka Connect)
# /16 supports up to 64 subnets
# WARNING: removing or reordering elements of for_each
#          will cause destructive re-creation of subnets.
resource "google_compute_subnetwork" "cymbal_subnets" {
  for_each                 = toset([var.gcp_region])
  name                     = "cymbal-retail-subnet-${each.key}"
  project                  = var.project_id
  ip_cidr_range            = cidrsubnet("10.10.0.0/16", 6, index([var.gcp_region], each.key))
  region                   = each.key
  network                  = google_compute_network.cymbal_retail_vpc.id
  private_ip_google_access = true
}

# Allow IAP for SSH
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.cymbal_retail_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

# Cloud Router and Cloud NAT for outbound internet access for VMs
resource "google_compute_router" "router" {
  name    = "cymbal-retail-router"
  region  = var.gcp_region
  network = google_compute_network.cymbal_retail_vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "cymbal-retail-nat"
  router                             = google_compute_router.router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# BigQuery datasets
resource "google_bigquery_dataset" "cymbal_bronze" {
  dataset_id = var.dataset_id_bronze
  location   = var.gcp_region
  depends_on = [google_project_service.workshop_apis]
}
resource "google_bigquery_dataset" "cymbal_silver" {
  dataset_id = var.dataset_id_silver
  location   = var.gcp_region
  depends_on = [google_project_service.workshop_apis]
}
resource "google_bigquery_dataset" "cymbal_gold" {
  dataset_id = var.dataset_id_gold
  location   = var.gcp_region
  depends_on = [google_project_service.workshop_apis]
}

# =====================================================================
# MODULE 0 RESOURCES
# =====================================================================

# =====================================================================
# MODULE 1 RESOURCES
# =====================================================================

resource "google_storage_bucket" "module1_bucket" {
  name                        = "${var.project_id}-module1-bucket"
  project                     = var.project_id
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.workshop_apis]
}

resource "terraform_data" "copy_module1_data" {
  triggers_replace = [
    google_storage_bucket.module1_bucket.id
  ]

  provisioner "local-exec" {
    command = <<-EOT
      gcloud storage cp -r --project="${var.project_id}" gs://rakeshmohandas-insurance-damage/elevate/warranty_generic gs://${google_storage_bucket.module1_bucket.name}/warranty_generic
      gcloud storage cp -r --project="${var.project_id}" gs://rakeshmohandas-insurance-damage/elevate/store_pos_manual_generic gs://${google_storage_bucket.module1_bucket.name}/store_pos_manual_generic
    EOT
  }

  depends_on = [
    google_storage_bucket.module1_bucket
  ]
}

# BigLake Iceberg Table: gold_inventory_reconciliation_ledger
resource "google_bigquery_table" "gold_inventory_reconciliation_ledger" {
  dataset_id          = google_bigquery_dataset.cymbal_gold.dataset_id
  table_id            = "gold_inventory_reconciliation_ledger"
  project             = var.project_id
  deletion_protection = false

  clustering = ["reconciliation_status", "store_id"]

  schema = <<EOF
[
  {
    "name": "business_date",
    "type": "DATE",
    "mode": "NULLABLE"
  },
  {
    "name": "store_id",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "store_name",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "city",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "item_id",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "unit_price_usd",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "opening_qty",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "shelf_qty",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "backroom_qty",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "intraday_gross_revenue_usd",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "est_cover_hours_remaining",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "reconciliation_status",
    "type": "STRING",
    "mode": "NULLABLE"
  }
]
EOF

  biglake_configuration {
    connection_id = google_bigquery_connection.biglake_connection.name
    storage_uri   = "gs://${google_storage_bucket.module1_bucket.name}/gold_inventory_reconciliation_ledger/"
    file_format   = "PARQUET"
    table_format  = "ICEBERG"
  }

  labels = {
    datacloud = "antigravity"
  }

  depends_on = [
    google_project_iam_member.biglake_connection_gcs_access
  ]
}

# Copy table data from shared project
resource "terraform_data" "copy_historical_transactional_data" {
  triggers_replace = [
    google_bigquery_dataset.cymbal_gold.id
  ]

  provisioner "local-exec" {
    command = "bq cp -f --project_id=${var.project_id} elevate-dev-kaijun:da_elevate_models.historical_transactional_data ${var.project_id}:${google_bigquery_dataset.cymbal_gold.dataset_id}.historical_transactional_data"
  }

  depends_on = [
    google_bigquery_dataset.cymbal_gold
  ]
}

resource "google_bigquery_dataset" "module1_unstructureddata" {
  dataset_id  = "module1_unstructureddata"
  location    = var.gcp_region
  description = "Module 1 Unstructured Data & Vector Search"
  depends_on  = [google_project_service.workshop_apis]
}

# Governance and Data Masking Service Accounts
locals {
  governance_service_accounts = {
    "sa-data-lead"  = "Data Lead Service Account"
    "sa-analyst"    = "Analyst Service Account"
    "sa-restricted" = "Restricted Service Account"
  }
  governance_sa_roles = [
    "roles/bigquery.jobUser",
    "roles/bigquery.dataViewer"
  ]
  governance_sa_role_pairs = flatten([
    for sa_key, sa_desc in local.governance_service_accounts : [
      for role in local.governance_sa_roles : {
        sa_key = sa_key
        role   = role
      }
    ]
  ])
}

resource "google_service_account" "governance_service_accounts" {
  for_each     = local.governance_service_accounts
  account_id   = each.key
  display_name = each.value
  project      = var.project_id
  depends_on   = [google_project_service.workshop_apis]
}

resource "google_project_iam_member" "governance_sa_bq_roles" {
  for_each = {
    for pair in local.governance_sa_role_pairs : "${pair.sa_key}-${pair.role}" => pair
  }
  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.governance_service_accounts[each.value.sa_key].email}"

  depends_on = [
    google_service_account.governance_service_accounts
  ]
}

# Create Cloud Composer service agent
resource "google_workload_identity_service_agent" "composer" {
  parent = "projects/${data.google_project.project.number}/locations/global/serviceProducers/composer.googleapis.com"
  depends_on = [
    google_project_service.workshop_apis
  ]
}

resource "google_project_iam_member" "composer_service_agent_v2_ext" {
  project = var.project_id
  role    = "roles/composer.ServiceAgentV2Ext"
  member  = "serviceAccount:service-${data.google_project.project.number}@cloudcomposer-accounts.iam.gserviceaccount.com"

  depends_on = [
    google_workload_identity_service_agent.composer
  ]
}

resource "google_composer_environment" "cymbal_airflow_env" {
  name    = "cymbal-airflow-env"
  region  = var.gcp_region
  project = var.project_id

  config {
    environment_size = "ENVIRONMENT_SIZE_SMALL"

    software_config {
      image_version = "composer-3-airflow-2.10.5"
      airflow_config_overrides = {
        dag_processor-refresh_interval = "30"
      }
    }

    node_config {
      service_account = google_service_account.cymbal_sa_data.email
    }
  }

  depends_on = [
    google_project_service.workshop_apis,
    google_project_iam_member.composer_service_agent_v2_ext,
    google_project_iam_member.cymbal_sa_data_iam_roles
  ]
}

# Allow intra-subnet traffic for Dataproc Serverless in module 1
resource "google_compute_firewall" "elevate_allow_internal" {
  name        = "elevate-allow-internal"
  network     = google_compute_network.cymbal_retail_vpc.name
  description = "Allow internal communication between Dataproc Serverless PySpark executors and driver"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [google_compute_subnetwork.cymbal_subnets[var.gcp_region].ip_cidr_range]
}

# Provision BigLake Iceberg REST Catalog
resource "google_biglake_iceberg_catalog" "cymbal_lakehouse" {
  name             = "cymbal-lakehouse"
  project          = var.project_id
  catalog_type     = "CATALOG_TYPE_FEDERATED"
  primary_location = var.gcp_region

  federated_catalog_options {
    glue_catalog_info {
      warehouse    = "621785110540"
      aws_region   = "us-east-1"
      aws_role_arn = "arn:aws:iam::621785110540:role/gcp-trust-role"
    }

    refresh_options {
      refresh_schedule {
        refresh_interval = "300s"
      }
    }
  }

  depends_on = [google_project_service.workshop_apis]
}

# BigQuery Enterprise Reservation for GQL Queries
resource "google_bigquery_reservation" "gql_query_reservation" {
  name              = "gql-query-reservation"
  location          = var.gcp_region
  slot_capacity     = 0
  edition           = "ENTERPRISE"
  ignore_idle_slots = false

  autoscale {
    max_slots = 200
  }

  depends_on = [google_project_service.workshop_apis]
}

# Assignment of Query Job Type to the Enterprise Reservation
resource "google_bigquery_reservation_assignment" "gql_query_assignment" {
  assignee    = "projects/${var.project_id}"
  job_type    = "QUERY"
  reservation = google_bigquery_reservation.gql_query_reservation.id
}

# =====================================================================
# MODULE 2 RESOURCES
# =====================================================================

# Bigtable instance
resource "google_bigtable_instance" "operations_db" {
  name                = "operations-db"
  deletion_protection = false

  cluster {
    cluster_id = "operations-cluster"
    zone       = "${var.gcp_region}-a"
    num_nodes  = 1
  }
  depends_on = [google_project_service.workshop_apis]
}

# Create Managed Kafka service agent
resource "google_workload_identity_service_agent" "kafka" {
  parent = "projects/${data.google_project.project.number}/locations/global/serviceProducers/managedkafka.googleapis.com"
  depends_on = [
    google_project_service.workshop_apis
  ]
}

# Managed Kafka cluster and connect
resource "google_managed_kafka_cluster" "kafka_cluster" {
  cluster_id = var.kafka_cluster_id
  location   = var.gcp_region

  capacity_config {
    vcpu_count   = "3"
    memory_bytes = "12884901888"
  }

  gcp_config {
    access_config {
      network_configs {
        subnet = google_compute_subnetwork.cymbal_subnets[var.gcp_region].id
      }
    }
  }

  timeouts {
    create = "2h"
  }
}

# Raw Kafka topic
resource "google_managed_kafka_topic" "kafka_topic_pos_transactions" {
  topic_id           = "pos-transactions"
  cluster            = google_managed_kafka_cluster.kafka_cluster.cluster_id
  location           = var.gcp_region
  partition_count    = 5
  replication_factor = 3

  configs = {
    "retention.ms"   = "3600000" # 1 hour - for buffering only
    "cleanup.policy" = "delete"
  }
}

resource "google_managed_kafka_connect_cluster" "kafka_connect_cluster" {
  connect_cluster_id = var.kafka_connect_cluster_id
  location           = var.gcp_region
  kafka_cluster      = google_managed_kafka_cluster.kafka_cluster.id

  capacity_config {
    vcpu_count   = "3"
    memory_bytes = "3221225472"
  }

  gcp_config {
    access_config {
      network_configs {
        primary_subnet = google_compute_subnetwork.cymbal_subnets[var.gcp_region].id
      }
    }
  }

  timeouts {
    create = "2h"
  }
}

# Agent Platform Endpoints for Pub/Sub online prediction
resource "google_vertex_ai_endpoint" "order_anomaly_endpoint" {
  name         = var.order_anomaly_endpoint_name
  display_name = "Order anomaly detection endpoint"
  location     = var.gcp_region
  project      = var.project_id
  depends_on   = [google_project_service.workshop_apis]
}

# Agent Platform Endpoint for Dataflow streaming inference
resource "google_vertex_ai_endpoint" "cashier_abuse_endpoint" {
  name         = var.cashier_abuse_endpoint_name
  display_name = "Cashier abuse detection endpoint"
  location     = var.gcp_region
  project      = var.project_id
  depends_on   = [google_project_service.workshop_apis]
}

# Run model deployment script
resource "terraform_data" "deploy_models" {
  provisioner "local-exec" {
    working_dir = path.module
    command     = <<-EOT
      python3 -m venv .venv_temp
      trap 'rm -rf .venv_temp' EXIT
      source .venv_temp/bin/activate
      pip install -r requirements.txt
      python deploy_models.py \
        --register \
        --project_id="${var.project_id}" \
        --region="${var.gcp_region}" \
        --dataset_id="${var.dataset_id_gold}" \
        --order_anomaly_endpoint="${var.order_anomaly_endpoint_name}" \
        --cashier_abuse_endpoint="${var.cashier_abuse_endpoint_name}"
      deactivate
    EOT
  }

  depends_on = [
    google_vertex_ai_endpoint.order_anomaly_endpoint,
    google_vertex_ai_endpoint.cashier_abuse_endpoint,
    google_bigquery_dataset.cymbal_gold,
    google_project_service.workshop_apis
  ]
}

# =====================================================================
# MODULE 3 RESOURCES
# =====================================================================

# BigQuery dataset for governance
resource "google_bigquery_dataset" "cymbal_governance" {
  dataset_id = "cymbal_governance"
  location   = var.gcp_region
  depends_on = [google_project_service.workshop_apis]
}

# Create Dataplex service agent
resource "google_workload_identity_service_agent" "dataplex" {
  parent = "projects/${data.google_project.project.number}/locations/global/serviceProducers/dataplex.googleapis.com"
  depends_on = [
    google_project_service.workshop_apis
  ]
}

# Grant BigQuery roles to Dataplex service agent for Data Profile and Quality scans
resource "google_project_iam_member" "dataplex_service_agent_bq_roles" {
  for_each = toset([
    "roles/bigquery.jobUser",
    "roles/bigquery.dataViewer"
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-dataplex.iam.gserviceaccount.com"

  depends_on = [
    google_workload_identity_service_agent.dataplex
  ]
}

# Custom SQL masking routine for card numbers
resource "google_bigquery_routine" "mask_card_number" {
  project              = var.project_id
  dataset_id           = google_bigquery_dataset.cymbal_gold.dataset_id
  routine_id           = "mask_card_number"
  routine_type         = "SCALAR_FUNCTION"
  data_governance_type = "DATA_MASKING"
  language             = "SQL"
  definition_body      = "CASE WHEN val = 'NA' THEN 'NA' ELSE CONCAT('XXXXXXXXXXXX', SUBSTR(val, -4)) END"

  arguments {
    name      = "val"
    data_type = "{\"typeKind\" : \"STRING\"}"
  }

  return_type = "{\"typeKind\" : \"STRING\"}"

  depends_on = [
    google_bigquery_dataset.cymbal_gold,
    google_project_service.workshop_apis
  ]
}

# Google Tags for Data Governance
resource "google_tags_tag_key" "cymbal_pii" {
  parent      = "projects/${var.project_id}"
  short_name  = "cymbal_pii"
  description = "Cymbal Retail PII and PCI-DSS governance tag key for data masking"
  purpose     = "DATA_GOVERNANCE"

  depends_on = [google_project_service.workshop_apis]
}

# Tag Value for card numbers
resource "google_tags_tag_value" "card_number" {
  parent      = google_tags_tag_key.cymbal_pii.id
  short_name  = "card_number"
  description = "Governance tag value for payment card numbers (PCI-DSS masking)"
}

data "google_project_iam_policy" "policy" {
  project = var.project_id

  depends_on = [
    google_project_iam_member.biglake_connection_gcs_access,
    google_project_iam_member.cymbal_sa_data_iam_roles,
    google_project_iam_member.governance_sa_bq_roles,
    google_project_iam_member.composer_service_agent_v2_ext,
    google_project_iam_member.dataplex_service_agent_bq_roles,
    google_biglake_iceberg_catalog.cymbal_lakehouse,
    google_workload_identity_service_agent.kafka
  ]
}

# BigQuery Data Masking Policy (V2)
resource "google_bigquery_datapolicyv2_data_policy" "mask_card_number_mod3" {
  project          = var.project_id
  location         = var.gcp_region
  data_policy_id   = "mask_card_number_mod3"
  data_policy_type = "DATA_MASKING_POLICY"

  data_masking_policy {
    routine = google_bigquery_routine.mask_card_number.id
  }

  data_governance_tag {
    key   = "${var.project_id}/${google_tags_tag_key.cymbal_pii.short_name}"
    value = google_tags_tag_value.card_number.short_name
  }

  grantees = [
    for m in distinct(flatten([
      for b in jsondecode(data.google_project_iam_policy.policy.policy_data).bindings : b.members
      ])) : (
      startswith(m, "user:") ? replace(m, "user:", "principal://goog/subject/") :
      replace(m, "serviceAccount:", "principal://iam.googleapis.com/projects/-/serviceAccounts/")
    ) if startswith(m, "user:") || startswith(m, "serviceAccount:")
  ]

  depends_on = [
    google_project_service.workshop_apis,
    google_tags_tag_value.card_number,
    google_bigquery_routine.mask_card_number
  ]
}

# Assign data governance tag to card_number column on historical_transactional_data
resource "terraform_data" "bind_card_number_data_policy" {
  triggers_replace = [
    terraform_data.copy_historical_transactional_data.id,
    google_tags_tag_value.card_number.id,
    google_bigquery_datapolicyv2_data_policy.mask_card_number_mod3.id
  ]

  provisioner "local-exec" {
    command = <<-EOT
      bq query --use_legacy_sql=false --project_id="${var.project_id}" \
        "ALTER TABLE \`${var.project_id}.${google_bigquery_dataset.cymbal_gold.dataset_id}.historical_transactional_data\`
         ALTER COLUMN card_number SET OPTIONS (
           data_governance_tags = [(\"${var.project_id}/${google_tags_tag_key.cymbal_pii.short_name}\", \"${google_tags_tag_value.card_number.short_name}\")]
         );"
    EOT
  }

  depends_on = [
    terraform_data.copy_historical_transactional_data,
    google_tags_tag_value.card_number,
    google_bigquery_datapolicyv2_data_policy.mask_card_number_mod3
  ]
}

