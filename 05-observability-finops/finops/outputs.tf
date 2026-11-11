output "budgets" {
  value = [aws_budgets_budget.org_total.name, aws_budgets_budget.workloads.name]
}

output "anomaly_monitor_arn" {
  value = aws_ce_anomaly_monitor.accounts.arn
}

output "active_cost_allocation_tags" {
  value = [for t in aws_ce_cost_allocation_tag.this : t.tag_key]
}
