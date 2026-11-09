def size: ((.u|length)+(.a|length)+([.marks[]?.x//""]|add//""|length)+120);
($all|group_by(.sid)|map({key:.[0].sid,value:(sort_by(.ts))})|from_entries) as $by
| group_by(.sid)
| map(sort_by(.ts) as $new|$new[0].sid as $sid
      |($by[$sid]|map(.uuid)|index($new[0].uuid) // 0) as $i
      |{sid:$sid,file:$new[0].file,
        first:(if $i>3 then $by[$sid][0] else null end),
        context:($by[$sid][([$i-3,0]|max):$i]),new:$new}
      |.+{chars:((([.first]|map(select(.!=null)))+.context+.new|map(size)|add)//0)})
| reduce .[] as $s ([]; if (length>0 and ((.[-1].chars+$s.chars)<=50000)) then .[-1].sessions+=[$s]|.[-1].chars+=$s.chars else .+[{chars:$s.chars,sessions:[$s]}] end)
