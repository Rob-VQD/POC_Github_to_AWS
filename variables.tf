variable "shared_credentials_path" {
  type        = string
  description = "Give path for AWS credentials (On windows it ends with .aws\\credentials)"
}

variable "IP_address_port_1433" {
    type = list(string)
    description = "Give IP addresses to allow traffic to RDS, every IP in string form and total in list form (default is ONLY VQD IP address)"
}

variable "Database_Password" {
    type = string
    description = "Give the Password to login to the database"
}

variable "Database_Username" {
    type = string
    description  = "Give the Username to login to the database"
}

variable "Port_to_connect_to_db" {
    type = number
    description = "Give the port to connect to the db (default 3306)"
    default = 3306
}