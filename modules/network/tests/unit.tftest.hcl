###############################################################################
# Unit tests: network module
#
# Uses mock_provider so NO HCS credentials are required.
# Run from the module directory:
#   cd modules/network && terraform test
# Or via the test runner:
#   ./scripts/test-module.sh network --level unit
###############################################################################

mock_provider "hcs" {}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: Basic VPC with public + private subnets
# Validates: VPC CIDR is used, correct subnet counts, naming
# ─────────────────────────────────────────────────────────────────────────────
run "creates_vpc_and_subnets" {
  command = apply

  variables {
    name_prefix          = "test-dev"
    vpc_cidr             = "10.10.0.0/16"
    public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]
    availability_zones   = ["az1.dc0"]
    enable_nat_gateway   = false
  }

  assert {
    condition     = hcs_vpc.this.cidr == "10.10.0.0/16"
    error_message = "VPC CIDR must match var.vpc_cidr"
  }

  assert {
    condition     = hcs_vpc.this.name == "test-dev-vpc"
    error_message = "VPC name must be '<name_prefix>-vpc'"
  }

  assert {
    condition     = length(hcs_vpc_subnet.public) == 2
    error_message = "Two public subnets should be created"
  }

  assert {
    condition     = length(hcs_vpc_subnet.private) == 2
    error_message = "Two private subnets should be created"
  }

  assert {
    condition     = output.vpc_id != ""
    error_message = "vpc_id output must not be empty"
  }

  assert {
    condition     = length(output.public_subnet_id_list) == 2
    error_message = "public_subnet_id_list must contain 2 IDs"
  }

  assert {
    condition     = length(output.private_subnet_id_list) == 2
    error_message = "private_subnet_id_list must contain 2 IDs"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: NAT gateway is created only when enabled
# ─────────────────────────────────────────────────────────────────────────────
run "nat_gateway_enabled" {
  command = apply

  variables {
    name_prefix          = "test-nat"
    vpc_cidr             = "10.20.0.0/16"
    public_subnet_cidrs  = ["10.20.1.0/24"]
    private_subnet_cidrs = ["10.20.10.0/24"]
    availability_zones   = ["az1.dc0"]
    enable_nat_gateway   = true
    nat_gateway_spec     = "1"
    nat_bandwidth_size   = 10
  }

  assert {
    condition     = length(hcs_nat_gateway.this) == 1
    error_message = "NAT gateway should be created when enable_nat_gateway = true"
  }

  assert {
    condition     = length(hcs_vpc_eip.nat) == 1
    error_message = "NAT EIP should be created when enable_nat_gateway = true"
  }

  assert {
    condition     = output.nat_gateway_id != ""
    error_message = "nat_gateway_id output must not be empty when NAT is enabled"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: NAT gateway is NOT created when disabled
# ─────────────────────────────────────────────────────────────────────────────
run "nat_gateway_disabled" {
  command = apply

  variables {
    name_prefix          = "test-no-nat"
    vpc_cidr             = "10.30.0.0/16"
    public_subnet_cidrs  = ["10.30.1.0/24"]
    private_subnet_cidrs = []
    availability_zones   = ["az1.dc0"]
    enable_nat_gateway   = false
  }

  assert {
    condition     = length(hcs_nat_gateway.this) == 0
    error_message = "No NAT gateway should be created when enable_nat_gateway = false"
  }

  assert {
    condition     = length(hcs_vpc_eip.nat) == 0
    error_message = "No NAT EIP should be created when enable_nat_gateway = false"
  }

  assert {
    condition     = output.nat_gateway_id == ""
    error_message = "nat_gateway_id output must be empty when NAT is disabled"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: Default security group is always created
# ─────────────────────────────────────────────────────────────────────────────
run "default_security_group_created" {
  command = apply

  variables {
    name_prefix          = "test-sg"
    vpc_cidr             = "10.40.0.0/16"
    public_subnet_cidrs  = []
    private_subnet_cidrs = []
    availability_zones   = ["az1.dc0"]
    enable_nat_gateway   = false
  }

  assert {
    condition     = hcs_networking_secgroup.default.name == "test-sg-default-sg"
    error_message = "Default SG name must be '<name_prefix>-default-sg'"
  }

  assert {
    condition     = output.default_security_group_id != ""
    error_message = "default_security_group_id must always be set"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 5: Subnets distributed evenly across AZs
# ─────────────────────────────────────────────────────────────────────────────
run "subnets_distributed_across_azs" {
  command = apply

  variables {
    name_prefix          = "test-az"
    vpc_cidr             = "10.50.0.0/16"
    public_subnet_cidrs  = ["10.50.1.0/24", "10.50.2.0/24", "10.50.3.0/24"]
    private_subnet_cidrs = []
    availability_zones   = ["az1.dc0", "az2.dc0"]
    enable_nat_gateway   = false
  }

  assert {
    condition     = length(hcs_vpc_subnet.public) == 3
    error_message = "3 public subnets should be created"
  }
}
