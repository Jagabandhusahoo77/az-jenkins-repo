# .tflint.hcl — TFLint configuration
#
# TFLint catches issues that `terraform validate` misses:
#   - Invalid instance types (e.g. "Standard_FAKE_v999")
#   - Deprecated resource attributes
#   - Naming convention violations
#   - Azure-specific best practices

plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Enforce variable declarations have descriptions
rule "terraform_documented_variables" {
  enabled = true
}

# Enforce output declarations have descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Warn on deprecated interpolation syntax (e.g. "${var.foo}" → var.foo)
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Require module sources to pin versions (no bare git refs)
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "semver"
}

# Enforce consistent naming (snake_case)
rule "terraform_naming_convention" {
  enabled = true

  variable {
    format = "snake_case"
  }

  resource {
    format = "snake_case"
  }

  output {
    format = "snake_case"
  }
}

# Require required_version in terraform blocks
rule "terraform_required_version" {
  enabled = true
}

# Require provider version constraints
rule "terraform_required_providers" {
  enabled = true
}
