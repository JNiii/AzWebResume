#initialize terraform
data "azurerm_client_config" "current" {
}

data azurerm_subscription "current"{ 
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.88.0"
    }
  }
    backend "azurerm" {
    resource_group_name  = "Terraform-Backend-Infra"
    storage_account_name = "sainfraazwebresume"
    container_name       = "terraform-state"
    key                  = "terraform.tfstate"
  }
}
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
#Create resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg-web-resume"
  location = var.regions
  tags     = var.AzureResumeTag
}

#Create storage acccount
resource "azurerm_storage_account" "sa_account" {
  name                     = "saazcloudwebresume"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "LRS"
  static_website {
    index_document     = "home.html"
    error_404_document = "404.html"
  }
  tags = var.AzureResumeTag

  provisioner "local-exec" {
  command = <<EOT
  az storage blob upload-batch --account-name ${azurerm_storage_account.sa_account.name} -d '$web' -s '../frontend/'
  EOT
  interpreter = ["powershell", "-command"]
  working_dir = path.module
  }
}

resource "azurerm_cdn_profile" "cdn" {
  name                = "cdn-azurewebresume"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard_Microsoft"

  tags = var.AzureResumeTag
}

resource "azurerm_cdn_endpoint" "cdn-end" {
  name                = "cdn-endpoint-azurewebresume"
  profile_name        = azurerm_cdn_profile.cdn.name
  location            = azurerm_cdn_profile.cdn.location
  resource_group_name = azurerm_resource_group.rg.name
  origin_host_header  = azurerm_storage_account.sa_account.primary_web_host

  origin {
    name      = "cdn-endpoint-1"
    host_name = azurerm_storage_account.sa_account.primary_web_host
  }

  delivery_rule {
    name  = "EnforceHTTPS"
    order = "1"

    request_scheme_condition {
      operator     = "Equal"
      match_values = ["HTTP"]
    }

    url_redirect_action {
      redirect_type = "Found"
      protocol      = "Https"
      }
    }  
  tags = var.AzureResumeTag


}

resource "azurerm_dns_zone" "dns-zone" {
  name                = var.domain
  resource_group_name = azurerm_resource_group.rg.name
  tags = var.AzureResumeTag

  depends_on = [ azurerm_cdn_endpoint.cdn-end ]
}

resource "azurerm_dns_a_record" "dns-a" {
  name                = "@"
  zone_name           = azurerm_dns_zone.dns-zone.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  target_resource_id  = azurerm_cdn_endpoint.cdn-end.id
  depends_on = [ azurerm_dns_zone.dns-zone ]

  provisioner "local-exec" {
    command = <<EOT
    az cdn custom-domain create --endpoint-name ${azurerm_cdn_endpoint.cdn-end.name} --hostname www.${var.domain} --resource-group ${azurerm_resource_group.rg.name} --profile-name ${azurerm_cdn_profile.cdn.name} -n "main-domain"
    EOT
    interpreter = ["bash", "-c"]
    working_dir = path.module
  }

  provisioner "local-exec" {
    command = <<EOT
    az cdn custom-domain enable-https --endpoint-name ${azurerm_cdn_endpoint.cdn-end.name} --resource-group ${azurerm_resource_group.rg.name} --profile-name ${azurerm_cdn_profile.cdn.name} -n "main-domain"
    EOT
    interpreter = ["bash", "-c"]
    working_dir = path.module
  }
}
resource "azurerm_dns_cname_record" "www_cname" {
  name                = "www"
  zone_name           = azurerm_dns_zone.dns-zone.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 3600
  target_resource_id  = azurerm_cdn_endpoint.cdn-end.id

  depends_on = [ azurerm_dns_zone.dns-zone ]
}


#Create CosmosDB account
resource "azurerm_cosmosdb_account" "cdb" {
  name                = "cdb-azurewebresume"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
  consistency_policy {
    consistency_level       = "Strong"
  }
  capabilities {
    name = "EnableServerless"
  }
  backup {
    type                = "Periodic"
    storage_redundancy  = "Local"
    interval_in_minutes = 1440
    retention_in_hours  = 48
  }
  cors_rule {
    allowed_headers    = ["*"]
    allowed_methods    = ["GET", "POST", "PUT"]
    allowed_origins    = ["https://www.imneojay.xyz"]
    exposed_headers    = ["*"]
    max_age_in_seconds = 180
  }
  tags = var.AzureResumeTag

}

#Create CosmosDB Database
resource "azurerm_cosmosdb_sql_database" "cdb-database" {
  name                = "AzureResume"
  resource_group_name = azurerm_cosmosdb_account.cdb.resource_group_name
  account_name        = azurerm_cosmosdb_account.cdb.name
}

#Create CosmosDB Database container
resource "azurerm_cosmosdb_sql_container" "cdb-container" {
  name                  = "Counter"
  resource_group_name   = azurerm_cosmosdb_account.cdb.resource_group_name
  account_name          = azurerm_cosmosdb_account.cdb.name
  database_name         = azurerm_cosmosdb_sql_database.cdb-database.name
  partition_key_path    = "/id"
  partition_key_version = 1

  indexing_policy {
    indexing_mode = "consistent"
  }
  #Upon creation, provision insert_data.py
  provisioner "local-exec" {
    command = "python ./Scripts/insert_data.py '${azurerm_cosmosdb_account.cdb.endpoint}' '${azurerm_cosmosdb_account.cdb.primary_key}' '${azurerm_cosmosdb_sql_database.cdb-database.name}' '${azurerm_cosmosdb_sql_container.cdb-container.name}' '${data.azurerm_storage_account.backup-sa.primary_blob_connection_string}' '${var.data-backups[2]}'"
    interpreter = ["bash", "-c"]
    working_dir = path.module
  }
}

#Create App service plan
resource "azurerm_service_plan" "app-service-plan" {
  name                = "ASP-fa-getazureresume"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = var.AzureResumeTag
}
#Create Application insights
resource "azurerm_application_insights" "app-insights" {
  name                = "insights-fa-azurecloudwebresume"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "other"

  tags = var.AzureResumeTag
}
###
resource "azurerm_linux_function_app" "func-app" {

  name                = "fa-azurecloudwebresume"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  storage_account_name       = azurerm_storage_account.sa_account.name
  storage_account_access_key = azurerm_storage_account.sa_account.primary_access_key
  service_plan_id            = azurerm_service_plan.app-service-plan.id
  https_only = true
  

  site_config {
    cors {
      allowed_origins = ["https://www.imneojay.xyz"]
      support_credentials = true
    }
    application_insights_connection_string = azurerm_application_insights.app-insights.connection_string
    application_insights_key               = azurerm_application_insights.app-insights.instrumentation_key
    application_stack {
        python_version = 3.11 #FUNCTIONS_WORKER_RUNTIME        
    }
    app_scale_limit = 5
  }
  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE": 1
    "ENABLE_ORYX_BUILD": true
    "SCM_DO_BUILD_DURING_DEPLOYMENT": true
    "COSMOSDB_URI" = "${azurerm_cosmosdb_account.cdb.endpoint}"
    "COSMOSDB_KEY" = "${azurerm_cosmosdb_account.cdb.primary_key}"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "${azurerm_application_insights.app-insights.connection_string}"
  }

  tags = var.AzureResumeTag
}

data "azurerm_resources" "func-app-data" {
  name = azurerm_linux_function_app.func-app.name
}
#Create a delay before uploading function app
resource "time_sleep" "wait_60_seconds" {
  depends_on = [azurerm_linux_function_app.func-app]
  create_duration = "60s"
}

resource "null_resource" "upload-func-app" {

  depends_on = [time_sleep.wait_60_seconds]

  provisioner "local-exec" {
    command = "func azure functionapp publish ${azurerm_linux_function_app.func-app.name} --nozip --python"
    interpreter = ["powershell", "-command"]
    working_dir = "../backendApi"
  }
}

resource "null_resource" "az-publishing-profile" {
  depends_on = [ null_resource.upload-func-app ]
  provisioner "local-exec" {
    command = <<EOT
      $subscription = Get-AzSubscription 
      Select-AzSubscription $subscription.Name
      Get-AzWebAppPublishingProfile -ResourceGroupName ${azurerm_resource_group.rg.name} -name ${azurerm_linux_function_app.func-app.name} -OutputFile './Secrets/fa-azurecloudwebresume.PublishSettings' -Format 'Ftp'
    EOT
    interpreter = ["powershell", "-command"]
    working_dir = path.cwd
  }
}

resource "azurerm_monitor_action_group" "send-email-to-admin" {
    name = "Send alert email to admin"
    resource_group_name = azurerm_resource_group.rg.name
    short_name = "email-admin"

    email_receiver {
    name          = "sendtoadmin"
    email_address = var.AdminEmail
  }
}

data "azurerm_resources" "cdb-data" {
  name = azurerm_cosmosdb_account.cdb.name
}

resource "azurerm_monitor_metric_alert" "server-request-alert" {
    name = "server-requests"
    resource_group_name = data.azurerm_resources.cdb-data.resources[0].resource_group_name
    scopes = [data.azurerm_resources.cdb-data.resources[0].id]
    description = "Action will be triggered when Cosmos DB requests count are exceeded within a period of time"
    severity = 3
    frequency = "PT5M"
    window_size = "PT5M"

    criteria {
        metric_namespace = data.azurerm_resources.cdb-data.resources[0].type
        metric_name = "TotalRequests"
        aggregation = "Count"
        operator = "GreaterThan"
        threshold = 50
        
        dimension {
            name = "DatabaseName"
            operator = "Include"
            values = ["AzureResume"]
        }
    }
    action {
        action_group_id = azurerm_monitor_action_group.send-email-to-admin.id
    }
    depends_on = [ azurerm_cosmosdb_account.cdb]
}

resource "azurerm_monitor_metric_alert" "server-availability-alert" {
    name = "server-availability"
    
    resource_group_name = data.azurerm_resources.cdb-data.resources[0].resource_group_name
    scopes = [data.azurerm_resources.cdb-data.resources[0].id]
    description = "Action will be triggered when Cosmos DB availability are lower than expected within a period of time"
    severity = 3
    frequency = "PT1H"
    window_size = "PT1H"

    criteria {
        metric_namespace = data.azurerm_resources.cdb-data.resources[0].type
        metric_name = "ServiceAvailability"
        aggregation = "Average"
        operator = "LessThanOrEqual"
        threshold = 95
    }
    action {
        action_group_id = azurerm_monitor_action_group.send-email-to-admin.id
    }

    depends_on = [ azurerm_cosmosdb_account.cdb]
}




resource "azurerm_monitor_metric_alert" "fa-response-time-alert" {
    name = "fa-response-time"
    resource_group_name = data.azurerm_resources.func-app-data.resources[0].resource_group_name
    scopes = [data.azurerm_resources.func-app-data.resources[0].id]
    description = "Action will be triggered when Function App response time are higher than expected within a period of time"
    severity = 3
    frequency = "PT5M"
    window_size = "PT5M"

    criteria {
        metric_namespace = data.azurerm_resources.func-app-data.resources[0].type
        metric_name = "AverageResponseTime"
        aggregation = "Average"
        operator = "GreaterThan"
        threshold = 3
    }
    action {
        action_group_id = azurerm_monitor_action_group.send-email-to-admin.id
    }

    depends_on = [ azurerm_linux_function_app.func-app ]
}
    

#Adds a feature that backups file to a storage account container
data "azurerm_storage_account" "backup-sa" {  
    resource_group_name = var.data-backups[0]

    name = var.data-backups[1]
}

resource "null_resource" "upload-backup" {
    triggers = {
      AZURESACS = data.azurerm_storage_account.backup-sa.primary_blob_connection_string
      SA_CONTAINER = var.data-backups[2]
    }
    provisioner "local-exec" {
      when = destroy
      command = "python ./Scripts/upload_data.py '${self.triggers.AZURESACS}' '${self.triggers.SA_CONTAINER}'"
      working_dir = path.cwd
      interpreter = ["bash", "-c"]
  }
}
#Create RBAC role for Azure resource group
resource "null_resource" "az-service-principal" {
  provisioner "local-exec" {
    command = "az ad sp create-for-rbac --name GetAzureResume --role contributor --scopes '${azurerm_resource_group.rg.id}' --json-auth > ./Secrets/az-rbac-key.txt"
    interpreter = ["powershell", "-command"]
    working_dir = path.module
  }
}

resource "null_resource" "backup-item" {
  triggers = {
    URI = azurerm_cosmosdb_account.cdb.endpoint
    KEY = azurerm_cosmosdb_account.cdb.primary_key
    DB = azurerm_cosmosdb_sql_database.cdb-database.name
    CONTAINER = azurerm_cosmosdb_sql_container.cdb-container.name
  }
  #Insert command get_data.py
  provisioner "local-exec" {
    when = destroy
    command = "python ./Scripts/get_data.py '${self.triggers.URI}' '${self.triggers.KEY}' ${self.triggers.DB} ${self.triggers.CONTAINER}"
    interpreter = ["bash", "-c"]
    working_dir = path.module
  }
}


#Add API management services from Azure
