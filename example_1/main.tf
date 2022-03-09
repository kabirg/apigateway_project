######################################################
###### Setup #######
######################################################
provider "aws" {}

variable "env" {
  default = "dev"
}

variable "root_path" {
  default = "v1"
}

variable "domain" {
  # Registered in GoDaddy. Will setup DNS for it in Terraform
  default = "kabirg.me"
}

variable "subdomain" {
  default = "test-apigw"
}

######################################################
###### Base Lambda #######
######################################################
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "test_lambda" {
  filename      = "lambda_source_code.zip"
  function_name = "kabirg-test-tf"
  handler       = "lambda_source_code.lambda_handler" # Name of file and method
  runtime = "python3.7"
  role          = aws_iam_role.iam_for_lambda.arn

  # filebase64sha256() is available in TF v0.11.12+. Otherwise use base64sha256() & file():
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("lambda_source_code.zip")
}

resource "aws_lambda_permission" "lambda_permission" {
  statement_id  = "AllowAPIGInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # The /*/*/* part allows invocation from any stage, method and resource path
  # within API Gateway REST API.
  # source_arn = "${aws_api_gateway_rest_api.kabirg-apig-rest-tf.execution_arn}/dev/GET/v1"
  # Use '*' instead of the stage name in the AGPIGW arn so that you can hit the APIGW via CLI and the console (in the console you hit it from the resource section, not the stage section)
  source_arn = "${aws_api_gateway_rest_api.kabirg-apig-rest-tf.execution_arn}/*/${aws_api_gateway_method.example.http_method}/${var.root_path}"
}


######################################################
###### API Gateway #######
######################################################
resource "aws_api_gateway_rest_api" "kabirg-apig-rest-tf" {
  name = "kabirg-test-apigw-tf"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# The resource/endpoint to expose, which listens for requests
resource "aws_api_gateway_resource" "example" {
  rest_api_id = aws_api_gateway_rest_api.kabirg-apig-rest-tf.id
  parent_id   = aws_api_gateway_rest_api.kabirg-apig-rest-tf.root_resource_id
  path_part   = var.root_path
}

# Defining the specification of the endpoint (i.e what HTTP methods it listens for)
resource "aws_api_gateway_method" "example" {
  rest_api_id   = aws_api_gateway_rest_api.kabirg-apig-rest-tf.id
  resource_id   = aws_api_gateway_resource.example.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integrating the endpoint with the backend, to handle the request
resource "aws_api_gateway_integration" "example" {
  rest_api_id = aws_api_gateway_rest_api.kabirg-apig-rest-tf.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example.http_method
  integration_http_method = "POST"
  type        = "AWS_PROXY"
  uri = aws_lambda_function.test_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "example" {
  rest_api_id = aws_api_gateway_rest_api.kabirg-apig-rest-tf.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.example.id,
      aws_api_gateway_method.example.id,
      aws_api_gateway_integration.example.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.example,
    aws_api_gateway_integration.example
  ]
}

resource "aws_api_gateway_stage" "example" {
  rest_api_id   = aws_api_gateway_rest_api.kabirg-apig-rest-tf.id
  deployment_id = aws_api_gateway_deployment.example.id
  stage_name    = var.env
}


######################################################
######### Custom Domain #########
######################################################
# Manually create a public HZ and update GoDaddy w/the nameservers.
# Then use this to import the HZ. It makes validation much faster than having the TF workflow interrupted to update GoDaddy.
data "aws_route53_zone" "base_domain" {
  name = var.domain
}

# Create an ACM-issued cert for the domain
# Set create_before_destroy to true so that cert renewal doesn't delete cert
resource "aws_acm_certificate" "cert" {
  domain_name       = "*.${var.domain}"
  validation_method = "DNS"

  tags = {
    Name = var.domain
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create the validation-CNAME record requested by ACM
resource "aws_route53_record" "domain_cert_dns_validation" {

  # 'for_each' requires a set(string) or map(any). But domain_validation_options returns set(any):
    # {
    #   domain_name = xx
    #   resource_record_name = xx
    #   resource_record_type = xx
    #   resource_record_value = xx
    # }

  # To iterate over this, we'll convert it to map(any) using the "for_each = {for x in x: xxx => x}" trick.
  # Src: https://www.sheldonhull.com/blog/how-to-iterate-through-a-list-of-objects-with-terraforms-for-each-function/
  # Src: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-3-upgrade#resource-aws_acm_certificate
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options: dvo.domain_name => {
      name = dvo.resource_record_name
      type = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  name = each.value.name
  type = each.value.type
  records = [each.value.record]
  zone_id = data.aws_route53_zone.base_domain.id
  ttl     = 60
}

# Wait for the cert to be issued
resource "aws_acm_certificate_validation" "domain_cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.domain_cert_dns_validation : record.fqdn]
}

# Create the APIGW custom domain
resource "aws_api_gateway_domain_name" "example" {
  domain_name              = "${var.subdomain}.${var.domain}"
  regional_certificate_arn = aws_acm_certificate_validation.domain_cert_validation.certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Add a mapping on the custom domain to the APIGW
resource "aws_api_gateway_base_path_mapping" "example" {
  api_id      = aws_api_gateway_rest_api.kabirg-apig-rest-tf.id
  stage_name  = aws_api_gateway_stage.example.stage_name
  domain_name = aws_api_gateway_domain_name.example.domain_name
}

# Map the custom domain to the APIGW via Alias R53 record
resource "aws_route53_record" "example" {
  name    = aws_api_gateway_domain_name.example.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.base_domain.id

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.example.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.example.regional_zone_id
  }
}


######################################################
######### Outputs #########
######################################################
output "base_url" {
  value = aws_api_gateway_deployment.example.invoke_url
}

output "invocation_url" {
  value = "${aws_api_gateway_deployment.example.invoke_url}${var.env}/${var.root_path}"
}

output "custom_domain" {
  value = "https://${var.subdomain}.${var.domain}"
}
