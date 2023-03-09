
locals { #example : fill your information
  github_owner = "gnokoheat"
  github_repo = "ecs-nodejs-app-example"
  github_branch = "master"
}


resource "aws_s3_bucket" "pipeline" {
  bucket = "${var.service_name}-codepipeline-bucket"
}

  resource "aws_s3_bucket_policy" "pipelineBucketPolicy" {
    bucket = aws_s3_bucket.pipeline.bucket
    policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "${var.service_name}Codepipeline",
  "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": "arn:aws:s3:::${var.service_name}-codepipeline-bucket/*",
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
POLICY

  }

data "aws_iam_policy_document" "assume_by_pipeline" {
  statement {
    sid = "AllowAssumeByPipeline"
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name = "${var.service_name}-pipeline-ecs-service-role"
  assume_role_policy = "${data.aws_iam_policy_document.assume_by_pipeline.json}"
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    sid = "AllowS3"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]

    resources = ["*"]
  }

  statement {
    sid = "AllowECR"
    effect = "Allow"

    actions = ["ecr:DescribeImages"]
    resources = ["*"]
  }

  statement {
    sid = "AllowCodebuild"
    effect = "Allow"

    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild"
    ]
    resources = ["*"]
  }

  statement {
    sid = "AllowCodedepoloy"
    effect = "Allow"

    actions = [
      "codedeploy:CreateDeployment",
      "codedeploy:GetApplication",
      "codedeploy:GetApplicationRevision",
      "codedeploy:GetDeployment",
      "codedeploy:GetDeploymentConfig",
      "codedeploy:RegisterApplicationRevision"
    ]
    resources = ["*"]
  }

  statement {
    sid = "AllowResources"
    effect = "Allow"

    actions = [
      "autoscaling:*",
      "cloudformation:*",
      "cloudwatch:*",
      "devicefarm:*",
      "ec2:*",
      "ecs:*",
      "elasticbeanstalk:*",
      "elasticloadbalancing:*",
      "iam:PassRole",
      "opsworks:*",
      "rds:*",
      "s3:*",
      "servicecatalog:*",
      "sns:*",
      "sqs:*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "pipeline" {
  role = "${aws_iam_role.pipeline.name}"
  policy = "${data.aws_iam_policy_document.pipeline.json}"
}

resource "aws_codestarconnections_connection" "example" {
  name          = "example-connection"
  provider_type = "GitHub"
}


resource "aws_codepipeline" "this" {
  name = "${var.service_name}-pipeline"
  role_arn = "${aws_iam_role.pipeline.arn}"

  artifact_store {
    location = "${var.service_name}-codepipeline-bucket"
    type = "S3"
  }

  
  stage {
    name = "Source"

    action {
      name = "Source"
      category = "Source"
      owner = "AWS"
      provider         = "CodeStarSourceConnection"
      version = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.example.arn
        FullRepositoryId = "${local.github_owner}/${local.github_repo}"
        BranchName       = "${local.github_branch}"

      }
    }
  }

  stage {
    name = "Build"

    action {
      name = "Build"
      category = "Build"
      owner = "AWS"
      provider = "CodeBuild"
      version = "1"
      input_artifacts = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]

      configuration = {
        ProjectName = "${aws_codebuild_project.this.name}"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name = "ExternalDeploy"
      category = "Deploy"
      owner = "AWS"
      provider = "CodeDeployToECS"
      input_artifacts = ["BuildArtifact"]
      version = "1"

      configuration = {
        ApplicationName = "${var.service_name}-service-deploy"
        DeploymentGroupName = "${var.service_name}-service-deploy-group"
        TaskDefinitionTemplateArtifact = "BuildArtifact"
        TaskDefinitionTemplatePath = "taskdef.json"
        AppSpecTemplateArtifact = "BuildArtifact"
        AppSpecTemplatePath = "appspec.yml"
      }
    }
  }
}
