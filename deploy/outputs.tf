output "biglake_service_account_id" {
  description = "BigLake Iceberg REST Catalog Service Account ID"
  value       = google_biglake_iceberg_catalog.cymbal_lakehouse.biglake_service_account_id
}

