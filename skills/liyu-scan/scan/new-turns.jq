(reduce $seen[] as $s ({}; .[$s.uuid]=$s)) as $m
| map(select((.is_last|not) or .idle))
| group_by(.uuid)|map(sort_by(.sid)|first)
| map(($m[.uuid]) as $r
      | select(
          if $since!="" then (.ts>=$since) and (($r==null) or ($r.outcome=="skip"))
          else ($r==null) or ($r.last!=.last) end)
      | .+{prior:(if $r==null then null else $r.outcome end)})
| sort_by(.ts)
