resource "aws_iam_policy" "instance_terminator_lambda" {
  name        = "${var.name}-lambda"
  path        = "/"
  description = "${var.name}-lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "autoscaling:Describe*",
      "ec2:Describe*"
    ],
    "Resource": "*"
  }, {
    "Effect": "Allow",
    "Action": [
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ],
    "Resource": "*",
    "Condition": {
        "StringEquals": { "autoscaling:ResourceTag/can-be-terminated": "true" }
     }
  }, {
    "Effect": "Allow",
    "Action": [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ],
    "Resource": "*"
  }, {
    "Effect": "Allow",
    "Action": [
      "route53:*"
    ],
    "Resource": [
      "*"
    ]
  }]
}
EOF

}

resource "aws_iam_role" "instance_terminator_lambda" {
  name               = "${var.name}-lambda"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "instance_terminator_lambda" {
  role       = aws_iam_role.instance_terminator_lambda.name
  policy_arn = aws_iam_policy.instance_terminator_lambda.arn
}

data "external" "download" {
  program = ["bash", "${path.module}/scripts/download.sh"]
  query   = {
    url              = var.download_url != "" ? var.download_url : format(
    "https://github.com/WealthWizardsEngineering/instance-terminator/releases/download/%s/instance-terminator.zip",
    var.instance_terminator_version,
    )
    output_directory = path.module
    output_filename  = "instance-terminator.zip"
  }
}

resource "aws_lambda_function" "instance_terminator" {
  filename         = data.external.download.result.output_file
  function_name    = var.name
  role             = aws_iam_role.instance_terminator_lambda.arn
  handler          = "src/instance_terminator.handler"
  timeout          = 30
  source_code_hash = filebase64sha256(data.external.download.result.output_file)
  runtime          = var.runtime
}

resource "aws_cloudwatch_event_rule" "lambda_instance_terminator" {
  name                = "lambda_${var.name}"
  description         = "lambda_${var.name}"
  schedule_expression = var.lambda_schedule
}

resource "aws_cloudwatch_event_target" "lambda_instance_terminator" {
  rule = aws_cloudwatch_event_rule.lambda_instance_terminator.name
  arn  = aws_lambda_function.instance_terminator.arn
}

resource "aws_lambda_permission" "lambda_instance_terminator" {
  statement_id  = "45"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_terminator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_instance_terminator.arn
}

