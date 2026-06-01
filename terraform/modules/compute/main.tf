resource "aws_ecr_repository" "api_repo" {
  name         = "${var.project_name}-api-${var.environment}"
  force_delete = true
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/ecs/${var.project_name}-api-${var.environment}"
  retention_in_days = 7
}

resource "aws_security_group" "api_sg" {
  name        = "api-sg-${var.environment}"
  description = "Permite acceso HTTP a la API FastAPI"
  vpc_id      = var.vpc_id

  ingress {
    description = "FastAPI"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida total"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "api_cluster" {
  name = "${var.project_name}-cluster-${var.environment}"
}

resource "aws_ecs_task_definition" "api_task" {
  family                   = "${var.project_name}-api-task-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.lab_role_arn
  task_role_arn            = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name      = "fastapi-api"
      image     = "${aws_ecr_repository.api_repo.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DYNAMO_TABLE"
          value = var.sensor_table_name
        },
        {
          name  = "MONGO_URI"
          value = var.mongodb_uri
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api_logs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api_service" {
  name            = "${var.project_name}-api-service-${var.environment}"
  cluster         = aws_ecs_cluster.api_cluster.id
  task_definition = aws_ecs_task_definition.api_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [aws_security_group.api_sg.id]
    assign_public_ip = true
  }
}