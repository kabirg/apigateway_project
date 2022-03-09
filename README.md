# Serverless Apps with API Gateway & Lambda

Step-by-step instructions to deploy and understand the 2 architectures in this demo:

1. A simple public (regional) APIGW w/Lambda backend. Has:
  - A custom domain
  - Restricted to only my IP
2. A private APIGW
  - Also has a custom domain (using a VPCE & LB)
  - Attempt to make it externally accessible (is this possible???)


Lambda is a means of writing software without having to scale the backend, that aspect is fully-managed by AWS. However Lambda cannot be invoked directly. So it needs to be exposed.

API Gateway lets you configure/expose API endpoints and sit in front of your backend Lambda's. With it you can configure authorization, request-throttling, request-monitoring, etc...

Terminology:
- Within API Gateways, you create **resources** aka *endpoints**. These are what you expose in a URL.
- You then specify those endpoints, by configuring the HTTP **methods** that act on that resource (GET, POST, DELETE).
- You then **integrate** the endpoints with your backend (in our case, Lambda), to process the request.
- To make an API Gateway actionable, you need to **deploy** it and associate it with a **stage**. The **stages** were intended to correspond to your environemnts (i.e dev, test, prod). Each stage is it's own instantiation of the APIGW. For any updates of the APIGW to take effect, you must redeploy.


## Public API Gateway

1. Create the Lambda function.
  - I'm using Python.
  - Then either zip this up and leave it in the source directory or upload it to an S3 bucket.
  - In the Terraform code, the `filename`argument for `aws_lambda_function` lets you specify the file for your lambda. If you choose the S3 route, this resource provides params to point to the S3 bucket/key.
  - The `source_code_hash` of `aws_lambda_function` ensures that any new zip files will be recognized by Terraform and a new `apply` will push the new zip file. Leave this out and Terraform will ignore any new zip files.
2. Test that the Lambda works.
  - `aws lambda invoke --function-name kabirg-test <output_file.json>`
3. Create the API Gateway.
  - Create the `aws_api_gateway_rest_api` and pick a type (default, regional, or private). We're going with REGIONAL for this one.
  - Then create your `resource`.
  - Then create the `method` that acts on that resource.
  - Then create the `integration` that ties to the resource and HTTP verb of the `method`, hook this up to the lambda.
    - When integrating APIGW with Lambda, you can use either the `AWS` or `AWS_PROXY` integration type. We're going with the latter is simpler to setup (set the integration method's verb to `POST`, map it to the Lambda's invoke-arn, and grant it permissions to use the lambda). The `AWS` integration on the other hand is more involved and requires you to setup the integration request/responses, but it puts less requst-handling logic in the code and does that manipulation within APIGW.
    - The `integration_http_method` is not the same as the regular method that acts on the resource. It's the method that the integration uses to act on the lambda. This needs to be `POST` when working with a lambda-proxy integration.
  4. Add the custom domain.
    - For my demo, I'm assuming I already have a domain in GoDaddy and want to do as little work here as possible.
    - Use `data.aws_route53_zone` to import a manually created public HZ for that domain.
    - Use the boilerplate code I have for creating a cert and getting it auto-validated using DNS validation.
    - Then create the custom domain & mapping.
    - Once created, manually re-deploy the APIGW.
    - You can now hit the custom domain:
    `https://test-apigw.kabirg.me/v1`
    - Workflow: `Request -> HZ -> Alias record (custom domain) -> APIGW`



Authorization
- Create an API key
- Attatch it to a usage plan for that key (required), link that plan to the APIG
- Link the key to the APIG stage
- Redeploy the APIG to implement
- Pass key in header
  - Passing API key (via header) to APIG once you've enforced API key:
  `curl -H "x-api-key: plHMkzdfeo6kQn3nzSVpa8APeESMbNyD1XQybbVb" https://1i8g5yhlui.execute-api.us-east-1.amazonaws.com/Test`
  `curl -X GET -H "x-api-key: plHMkzdfeo6kQn3nzSVpa8APeESMbNyD1XQybbVb" https://1i8g5yhlui.execute-api.us-east-1.amazonaws.com/Test`
  - You can also choose to use an authorizer rather than a header....



## Private API Gateway




## Sources
- Authorizers:
  - https://medium.com/swlh/how-to-protect-apis-with-jwt-and-api-gateway-lambda-authorizer-1110ff035df1
  - https://faun.pub/securing-api-gateway-with-lambda-authorizers-62845032bc7d
- APIs
  - https://www.educative.io/blog/what-are-rest-apis
  - https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html
- API Gateway
  - https://blog.tinystacks.com/aws-api-gateway-rest-http
  - https://stackoverflow.com/questions/39061041/using-an-api-key-in-amazon-api-gateway
  - Simple tutorial for public APIG/lambda and API Key header authorization: https://medium.com/swlh/make-rest-apis-using-aws-lambda-and-api-gateway-c9e1bab52bed
  - Creating HTTP API’s (quick read): https://medium.com/@xiaolancara/using-aws-api-gateway-to-build-an-end-to-end-http-api-efd8fbd917c6
  - Some nitty gritty details for other stuff I probably won’t use but very useful to skim: https://blog.sourcerer.io/full-guide-to-developing-rest-apis-with-aws-api-gateway-and-aws-lambda-d254729d6992
- Custom Domain
  - https://yogeshnile.cloud/how-to-create-custom-domain-api-in-aws-api-gateway-40ba2132b470
- Other
  - Going live w/APIG: https://medium.com/theburningmonk-com/check-list-for-going-live-with-api-gateway-and-lambda-e139c439b1e4
  - Good tips: https://towardsaws.com/a-quick-aws-api-gateway-cheatsheet-b78cb39154f2
- Lambda
  - Integrations: https://medium.com/@lakshmanLD/lambda-proxy-vs-lambda-integration-in-aws-api-gateway-3a9397af0e6d
  - https://www.stackery.io/blog/why-you-should-use-api-gateway-proxy-integration-with-lambda/
# apigateway_project
