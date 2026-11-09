($results|map({key:.uuid,value:.outcome})|from_entries) as $o
| group_by(.sid)
| map(select(all(.[]; $o[.uuid]!=null)))
| add // []
| map({uuid,last,sid,outcome:(if .prior=="inbox" then "inbox" else $o[.uuid] end)})
| .[]
