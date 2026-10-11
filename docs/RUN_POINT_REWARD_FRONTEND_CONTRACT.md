# Run point reward frontend contract

## Source contract

The frontend mapping was checked against `MovToRun/backend` at commit
`2a9c1ff7fec572b5ecc56a9d4f684d8d572b3820`, including
`docs/API_CONTRACT.md`, `RunSummaryResponse`, `RunListResponse`,
`RunDetailResponse`, and `PointRunRewardView`.

`pointReward` is a nullable field on each run summary. Upload responses return a
run summary directly, list responses wrap summaries in `results`, and detail
responses unwrap the summary onto the top-level object. The reward object has
`status` and nullable `pointsAwarded` fields:

| Response | Meaning | Frontend treatment |
|---|---|---|
| `pointReward: null` or absent | No reward request exists | Omit the backend-derived reward row/marker |
| `PENDING`, amount `null` | Pending or retry-needed | Show “확인 중”; never show an amount |
| `SETTLED`, amount `0` or greater | Final settlement, including zero | Show the exact amount and the existing `PrismPoint` mark |
| `UNAVAILABLE`, amount `null` | Reward lookup failed while run data remains available | Show “확인 불가”; never infer an amount |

Amounts for `PENDING` and `UNAVAILABLE`, missing amounts for `SETTLED`, negative
settlements, unknown status values, and objects missing `pointsAwarded` are
rejected as malformed contract data.

## Frontend behavior

`RunRecord.pointReward` is optional so older locally saved runs continue to
decode unchanged. Local demo runs keep their prior sample values and do not get
a synthetic backend reward. A reward supplied by a future response is retained
through record persistence and shown on completion, the run list, and detail.
The list keeps its existing reward slot and the `PrismPoint` asset. Completion
and detail use a compact “러닝 포인트” row with the same mark for settled
amounts. With no response property, no backend-derived row appears. The older
30-point sample marker remains confined to the existing review fixture and is
not treated as `pointReward`.

This change only prepares the model and UI boundary. It does not add an upload,
list, or detail HTTP request; configure a service host; or call the backend.
The `-wire-run-point-reward` launch fixture is local-only and covers all four
contract states plus the no-request case.

## Verification boundary

Unit tests cover each DTO state, settled zero, status/amount validation, legacy
record decoding, and local-run persistence. A focused UI test exercises
completion, list, and detail for each state and confirms that the pre-existing
review-only sample marker remains unchanged when there is no response object.
Full pixel and motion QA against the source wireframes remains outstanding.
