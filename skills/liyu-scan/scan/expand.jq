def clean: gsub("\\s+";" ");
def kind: if (.isMeta==true or .origin.kind!="human") then "SYS" else "U" end;
[inputs|fromjson?|select(.uuid and .timestamp and (.type=="user" or .type=="assistant" or (.type=="attachment" and .attachment.type=="queued_command")))]|sort_by(.timestamp)
|(map(.uuid)|index($from)) as $a|(map(.uuid)|index($to)) as $b
|if ($a==null or $b==null) then "ERROR: 找不到 uuid from=\($from) to=\($to)" else
 .[$a:($b+1)]
 |map(. as $e|if .type=="attachment" then [{r:(if .attachment.origin.kind=="human" then "U" else "SYS" end),x:(.attachment.prompt|if type=="string" then . else ([.[]?|select(.type=="text").text]|join(" ")) end)}] elif .type=="user" then
      (.message.content|if type=="string" then [{r:($e|kind),x:.}] else map(if .type=="text" then {r:($e|kind),x:.text} elif .type=="tool_result" then (if .is_error==true then {r:"FAIL",x:((.content|tostring)[0:400])} else {r:"R",x:((.content|tostring)[0:400])} end) else empty end) end)
    else (.message.content|if type=="array" then map(if .type=="text" then {r:"A",x:.text} elif .type=="tool_use" then {r:"T",x:(.name+" "+(.input|tostring|.[0:600]))} else empty end) else [] end) end)
 |add // []
 |(env.EXPAND_FULL=="1") as $full
 |map("\(.r): \(.x|clean|if $full then . else .[0:2000] end)")|join("\n")
 |if ($full|not) and length>30000 then .[0:30000]+"\n[TRUNCATED: 超過 30000 字，請縮小範圍]" else . end
 end
