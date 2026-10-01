# What the reviews found

Each row is a real hole found in the gate by an independent AI review pass. The first column says what the hole was, the second says what a careless or hostile author could do with it, and the third says how it was closed. Details of the product and its tests are left out on purpose.

| # | The hole | What an author could do with it | How it was closed |
|---|---|---|---|
| 1 | The approval was a sentence in the description | Type "approved by the reviewer" and merge | Counts only if a designated reviewer really approved the latest commit |
| 2 | A generic approval could be reused | Get a normal "looks good", then edit the description to add a risky exception | The reviewer's own text must quote the exact line |
| 3 | Counters that said how many times a test had passed were author-editable | Bump a counter to mark a test "proven" without ever running it | Any such change is treated as an unverified claim needing a verified approval |
| 4 | A new file could be quietly mapped into a lighter category | Add a file and a mapping for it in the same change so it escapes the full test run | Compare how every file is classified before and after; any downgrade needs approval |
| 5 | The pointer to the list of required tests could be repointed | Point it at a smaller, change-made list that hides required tests | Changing the pointer is itself a change that needs approval |
| 6 | A table with no "mechanism" column was skipped | Remove the column and a required test disappears from the coverage check | Such rows are reported as problems and fail validation |
| 7 | A parser assumed a fixed column position | A differently shaped table was read wrongly, so required tests were missed or wrongly rejected | Each table's own header decides where its columns are |
| 8 | One exception line waived every untested scenario | One bare sentence silenced the whole check | An exception must name the exact scenarios and give a reason |
| 9 | Deleting a test escaped review depending on its classification | Delete a support file in the test folder that was filed as documentation | Deletions are detected by path before classification |
| 10 | The removal approval matched paths by "contains" | `old_test.dart.bak` satisfied a deletion of `old_test.dart` | Whole-path matching that must equal the deleted set |
| 11 | A green result could go stale | Merge on an old green result after the target branch changed | Require up-to-date branches; fail closed if the base differs |
| 12 | The reviewer requirement covered only governance files | An ordinary code change with a wrong "no risk" claim merged unreviewed | The designated reviewer owns every path |
| 13 | A statement in two places disagreed | One document said a rule applied to every change, another exempted some | One rule, stated once, with the exception named |
| 14 | Instructions for planners could lower a standard before it was active | A planner picked a cheaper test type while the old rule still applied | Every instruction checks the activation status first |

What the reviews could not fix, and the gate says so: editing a test to weaken its assertions is undetectable by a rule like this. That stays a human reviewer's job.
