def clean: gsub("\\s+";" ");
def body: if type=="string" then . else ([.[]?|select(.type=="text").text]|join(" ")) end;
def trtext: if (.content|type)=="string" then .content else ([.content[]?|.text? // empty]|join(" ")) end;
def human: (.type=="user" and .origin.kind=="human" and (.isMeta!=true) and ((.message.content|body|test("^\\s*<bash-"))|not) and ((.message.content|body|clean)!=""));
def queued: (.type=="attachment" and .attachment.type=="queued_command" and .attachment.origin.kind=="human");
def clip: if length>600 then .[0:300]+" … "+.[-300:] else . end;
[inputs|fromjson?|select(.uuid and .timestamp and (.type=="user" or .type=="assistant" or .type=="attachment"))]
|sort_by(.timestamp)
|(map(select(human))|group_by(.parentUuid)|map(select(length>1)|.[1:]|map(.uuid))|add // []) as $retry
|reduce .[] as $e ([];
  if ($e|queued) or ($e|human) then
    . + [{sid:$e.sessionId,file:$file,uuid:$e.uuid,ts:$e.timestamp,cwd:$e.cwd,last:$e.uuid,
          u:((if ($e|queued) then $e.attachment.prompt else $e.message.content end)|body|clean|.[0:1500]),
          suggest:($e.promptSource=="suggestion_accepted"),
          marks:(if ($retry|index($e.uuid)) then [{r:"RETRY"}] else [] end),a:"",fails:0,edits:{},tools:{}}]
  elif length==0 or $e.type=="attachment" then .
  else
    .[-1].last=$e.uuid
    | if $e.type=="assistant" then
        reduce (($e.message.content|if type=="array" then . else [] end)[]) as $b (.;
          if $b.type=="text" then .[-1].a=($b.text|clean|clip)
          elif $b.type=="tool_use" then .[-1].tools[$b.name]+=1
            | if ($b.name=="Edit" or $b.name=="Write") then .[-1].edits[($b.input.file_path//"?")|tostring]+=1 else . end
          else . end)
      else
        reduce (($e.message.content|if type=="array" then . else [] end)[]) as $b (.;
          if $b.type=="tool_result" and $b.is_error==true then
            ($b|trtext) as $t
            | if ($t|test("doesn.t want to (proceed|take this action)")) then .[-1].marks+=[{r:"REJECT",x:($t|clean|.[0:600])}] else .[-1].fails+=1 end
          elif $b.type=="text" and ($b.text|startswith("[Request interrupted")) then .[-1].marks+=[{r:"INT"}]
          else . end)
      end
  end)
|(length-1) as $n|to_entries|map(.value+{is_last:(.key==$n),idle:$idle})|.[]
