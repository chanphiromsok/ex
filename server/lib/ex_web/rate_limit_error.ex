# AshRateLimiter raises LimitExceeded as a `:forbidden` Ash error, which AshJsonApi would render as
# 403. Clients (and the per-IP plug) expect 429 for "slow down".
defimpl AshJsonApi.ToJsonApiError, for: AshRateLimiter.LimitExceeded do
  def to_json_api_error(_error) do
    %AshJsonApi.Error{
      id: Ash.UUID.generate(),
      status_code: 429,
      code: "rate_limited",
      title: "Too Many Requests",
      detail: "Too many attempts. Try again later."
    }
  end
end
