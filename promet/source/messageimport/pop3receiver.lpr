{*******************************************************************************
Dieser Sourcecode darf nicht ohne gültige Geheimhaltungsvereinbarung benutzt werden
und ohne gültigen Vertriebspartnervertrag weitergegeben werden.
You have no permission to use this Source without valid NDA
and copy it without valid distribution partner agreement
Christian Ulrich
info@cu-tec.de
Created 01.06.2006
*******************************************************************************}

//--ignorestart ignoriert start Value
program pop3receiver;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, CustApp, uBaseCustomApplication, pmimemessages, mimemess,
  pop3send, mimepart, uData, uBaseDBInterface, Utils, uMessages, uBaseDBClasses,
  uPerson, synautil, uIntfStrConsts, FileUtil, db, uDocuments, ssl_openssl,
  uMimeMessages,synaip, laz_synapse,uBaseApplication,LConvEncoding,RegExpr,mailchck;

type
  TPOP3Receiver = class(TBaseCustomApplication)
  private
    TextThere : Boolean;
    HtmlThere : Boolean;
    aSender: String;
    aSubject: String;
    MList: TStringList;
    messageidx: LongInt;
    msg: TMimeMess;
    fullmsg: TMimeMess;
    NewMessages,
    NewUnknownMessages : Integer;
    pop: TPOP3Send;
  protected
    procedure DoRun; override;
    procedure WriteMessage(s : string);
    function AskForBigMail: Boolean;
    function CommandReceived(Sender: TObject; aCommand: string): Boolean;
    procedure ReceiveMails(aUser : string);
    function GetSingleInstance : Boolean; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

resourcestring
  strReceivingMailsFrom         = 'empfange mails von %s';
  strMailLoginFailed            = 'Anmeldung fehlgeschlagen, server antwortet nicht !';
  strLoginComplete              = 'Anmeldung erfolgreich ...';
  strRecivingMessageXofX        = 'Empfange Nachricht %d von %d';
  strMessageToBig               = 'Die e-Mail Nachricht von "%s" mit Betreff "%s" ist grösser als 10MB, soll Sie wirklich heruntergeladen werden ?';

{ TPOP3Receiver }

procedure TPOP3Receiver.DoRun;
var
  ActID: String;
  i: Integer;
  ArchiveMsg: TArchivedMessage;
  StartTime: TDateTime;
  aTime: Extended;
begin
  with BaseApplication as IBaseApplication do
    begin
      AppVersion:={$I ../base/version.inc};
      AppRevision:={$I ../base/revision.inc};
    end;
  if not Login then Terminate;
  RegisterMessageHandler;
  MessageHandler.RegisterCommandHandler(@Commandreceived);
  ArchiveMsg := TArchivedMessage.Create(nil,Data);
  ArchiveMsg.CreateTable;
  ArchiveMsg.Free;
  StartTime := Now();
  {
  if SSLImplementation = nil then
    debugln('warning no SSL Library loaded !');
  }
  {
  while not Terminated do
    begin
      aTime := (Now()-StartTime);
      if aTime > ((1/HoursPerDay)*2) then break;
  }
      with Data.Users.DataSet do
        begin
          First;
          while not EOF do
            begin
              ReceiveMails(FieldByName('NAME').AsString);
              Next;
            end;
        end;
  {
      if HasOption('o','onerun') then break;
      for i := 0 to 1000 do
        begin
          sleep(60*6);
          if Terminated then break;
        end;
    end;
  }
  // stop program loop
  if not Terminated then
    Terminate;
end;

procedure TPOP3Receiver.WriteMessage(s: string);
begin
  writeln(s);
end;

function TPOP3Receiver.AskForBigMail: Boolean;
begin
  Result := True;//MessageDlg(streMail,Format(strMessageToBig,[asender,asubject]),mtInformation,[mbYes,mbNo],0) = mrYes;
end;
procedure TPOP3Receiver.ReceiveMails(aUser : string);
var
  ErrorMsg: String;
  ReplaceOmailaccounts: Boolean;
  atmp: String;
  start: LongInt;
  i: Integer;
  MID: LongInt;
  DoDownload: Boolean;
  CustomerCont: TPersonContactData;
  Customers: TPerson;
  mailaccounts : string = '';
  omailaccounts : string = '';
  aTreeEntry: Integer;
  BMID: LongInt;
  SpamPoints: real;
  a,b: Integer;
  aMID: String;
  MessageIndex : TMessageList;
  DeletedItems : TDeletedItems;
  Message : TMimeMessage;
  aConnection: TComponent;
  ArchiveMsg: TArchivedMessage;
  DoArchive : Boolean = False;
  DoDelete : Boolean = False;
  ss: TStringStream;
  tmp: String;
  lSP: Integer;
  aChk: Integer;

  function DoGetStartValue: Integer;
  var
    b: Integer;
    OldFilter: String;
    Messages: TMessageList;
  begin
    Result := -1;
    Messages := TMessageList.Create(Self,Data,nil);
    for b := MList.Count-1 downto 0 do
      begin
        Data.SetFilter(Messages,'"ID"='''+trim(copy(MList[b],pos(' ',MList[b])+1,length(MList[b])))+'''');
        Data.SetFilter(DeletedItems,'"LINK"=''MESSAGEIDX@'+copy(MList[b],pos(' ',MList[b])+1,length(MList[b]))+'''');
        if (Messages.Count > 0)
        or (DeletedItems.Count > 0) then
          begin
            Result := b;
            break;
          end;
      end;
    Messages.Free;
  end;
begin
  aConnection := Data.GetNewConnection;
  MessageIndex := TMessageList.Create(Self,Data,aConnection);
  MessageIndex.CreateTable;
  DeletedItems := TDeletedItems.Create(Self,Data,aConnection);
  DeletedItems.CreateTable;
  Message := TMimeMessage.Create(Self,Data,aConnection);
  omailaccounts := '';
  mailaccounts := '';
  with Self as IBaseDbInterface do
    mailaccounts := DBConfig.ReadString('MAILACCOUNTS','');
  ReplaceOmailaccounts := false;
  while pos('|',mailaccounts) > 0 do
    begin  //Servertype;Server;Username;Password;Active
      if copy(mailaccounts,0,pos(';',mailaccounts)-1) = 'POP3' then
        begin
          mailaccounts := copy(mailaccounts,pos(';',mailaccounts)+1,length(mailaccounts));
          pop := TPOP3Send.Create;
          pop.TargetHost := copy(mailaccounts,0,pos(';',mailaccounts)-1);
          if pos(':',pop.TargetHost) > 0 then
            begin
              pop.TargetPort := copy(pop.TargetHost,pos(':',pop.TargetHost)+1,length(pop.TargetHost));
              pop.TargetHost := copy(pop.TargetHost,0,pos(':',pop.TargetHost)-1);
            end;
          writemessage(Format(strReceivingMailsFrom,[copy(mailaccounts,0,pos(';',mailaccounts)-1)]));
          mailaccounts := copy(mailaccounts,pos(';',mailaccounts)+1,length(mailaccounts));
          pop.UserName := copy(mailaccounts,0,pos(';',mailaccounts)-1);
          mailaccounts := copy(mailaccounts,pos(';',mailaccounts)+1,length(mailaccounts));
          pop.Password := copy(mailaccounts,0,pos(';',mailaccounts)-1);
          mailaccounts := copy(mailaccounts,pos(';',mailaccounts)+1,length(mailaccounts));
          pop.AuthType:=POP3AuthAll;
          pop.AutoTLS:=True;
          pop.Timeout:=12000;
          tmp := mailaccounts;
          tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
          if copy(tmp,0,2) <> 'L:' then
            begin
              if copy(tmp,0,4) = 'YES;' then
                begin
                  DoArchive := True;
                  tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
                end
              else if copy(tmp,0,3) = 'NO;' then
                begin
                  DoArchive := False;
                  tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
                end;
              if copy(tmp,0,4) = 'YES;' then
                begin
                  DoDelete := True;
                  tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
                end
              else if copy(tmp,0,3) = 'NO;' then
                begin
                  DoDelete := False;
                  tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
                end;
            end;
          omailaccounts := omailaccounts+'POP3;'+pop.TargetHost+';'+pop.UserName+';'+pop.Password+';'+copy(mailaccounts,0,pos(';',mailaccounts)-1)+';';
          if DoArchive then
            omailaccounts := omailaccounts+'YES;'
          else omailaccounts := omailaccounts+'NO;';
          if DoDelete then
            omailaccounts := omailaccounts+'YES;'
          else omailaccounts := omailaccounts+'NO;';
          omailaccounts := omailaccounts+'L:;';
          if copy(mailaccounts,0,pos(';',mailaccounts)-1) = 'YES' then
            if pop.Login then
              begin
                writemessage(strLoginComplete);
                pop.Uidl(0);
                MList := TStringList.Create;
                MList.Assign(pop.FullResult);
                if MList.Count > 0 then
                  omailaccounts := copy(omailaccounts,0,length(omailaccounts)-1)+MList[Mlist.Count-1]+';';
                ReplaceOmailaccounts := True;
                mailaccounts := copy(mailaccounts,pos(';',mailaccounts)+1,length(mailaccounts));
                if copy(mailaccounts,0,2) <> 'L:' then
                  begin
                    if copy(mailaccounts,0,4) = 'YES;' then
                      begin
                        mailaccounts := copy(mailaccounts,pos(';',mailaccounts)+1,length(mailaccounts));
                      end
                    else if copy(mailaccounts,0,3) = 'NO;' then
                      begin
                        mailaccounts := copy(mailaccounts,pos(';',mailaccounts)+1,length(mailaccounts));
                      end;
                    if copy(mailaccounts,0,4) = 'YES;' then
                      begin
                        mailaccounts := copy(mailaccounts,pos(';',mailaccounts)+1,length(mailaccounts));
                      end
                    else if copy(mailaccounts,0,3) = 'NO;' then
                      begin
                        mailaccounts := copy(mailaccounts,pos(';',mailaccounts)+1,length(mailaccounts));
                      end;
                  end;
                if not HasOption('i','ignorestart') then
                  begin
                    if copy(mailaccounts,0,2) = 'L:' then
                      begin
                        atmp := copy(mailaccounts,3,length(mailaccounts));
                        start := MList.IndexOf(copy(atmp,0,pos(';',atmp)-1));
                      end
                    else
                      Start := -1;
                    if Start = -1 then
                      begin
                        Start := -1;//DoGetStartValue;
                      end;
                  end
                else start := -1;
                if DoDelete then Start := -1;
                for i := start+1 to MList.Count-1 do
                  begin
                    try
                      messageidx := i;
                      MID := StrToInt(copy(MList[messageidx],0,pos(' ',MList[i])-1));
                      DoDownload := True;
                      pop.List(MID);
                      atmp := pop.ResultString;
                      if StrToIntDef(copy(atmp,rpos(' ',atmp)+1,length(atmp)),0) > 10*(1024*1024) then
                        begin
                          pop.Top(MID,0); //Header holen
                          msg := TMimeMess.Create;
                          msg.Lines.Text:=pop.FullResult.Text;
                          msg.DecodeMessage;
                          aSender :=  ConvertEncoding(msg.Header.From,GuessEncoding(msg.Header.From),EncodingUTF8);
                          aSubject := ConvertEncoding(msg.Header.Subject,GuessEncoding(msg.Header.Subject),EncodingUTF8);
                          DoDownload := AskForBigMail;
                          msg.Free;
                        end;
                      if DoDownload then
                        begin
                          writemessage(Format(strRecivingMessageXofX,[i,MList.Count]));
                          pop.Top(MID,0); //Header holen
                          msg := TMimeMess.Create;
                          msg.Lines.Text:=pop.FullResult.Text;
                          msg.DecodeMessage;
                          aSender :=  ConvertEncoding(msg.Header.From,GuessEncoding(msg.Header.From),EncodingUTF8);
                          aSubject := ConvertEncoding(msg.Header.Subject,GuessEncoding(msg.Header.Subject),EncodingUTF8);
                          aMID := copy(MList[messageidx],pos(' ',MList[messageidx])+1,length(MList[messageidx]));
                          Data.SetFilter(MessageIndex,'"ID"='''+aMID+'''');
                          Data.SetFilter(DeletedItems,'"LINK"=''MESSAGEIDX@'+aMID+'''');
                          Message.History.Open;
                          Message.History.AddItem(Message.DataSet,Format(strActionMessageReceived,[DateTimeToStr(Now())]),
                                                    'MESSAGEIDX@'+aMID+'{'+aSubject+'}',
                                                    '',
                                                    nil,
                                                    ACICON_MAILNEW);
                          if (not MessageIndex.DataSet.Locate('ID',aMID,[]))
                          and (not DeletedItems.DataSet.Locate('LINK','MESSAGEIDX@'+aMID,[])) then
                            begin
                              atmp:=ConvertEncoding(getemailaddr(msg.Header.From),GuessEncoding(getemailaddr(msg.Header.From)),EncodingUTF8);
                              try
                                CustomerCont := TPersonContactData.Create(Self,Data);
                                if Data.IsSQLDb then
                                  Data.SetFilter(CustomerCont,'UPPER("DATA")=UPPER('''+atmp+''')')
                                else
                                  Data.SetFilter(CustomerCont,'"DATA"='''+atmp+'''');
                              except
                              end;
                              Customers := TPerson.Create(Self,Data);
                              Data.SetFilter(Customers,'"ACCOUNTNO"='+Data.QuoteValue(CustomerCont.DataSet.FieldByName('ACCOUNTNO').AsString));
                              CustomerCont.Free;
                              if Customers.Count > 0 then
                                begin
                                  Customers.History.Open;
                                  Customers.History.AddItem(Customers.DataSet,Format(strActionMessageReceived,[aSubject]),
                                                            'MESSAGEIDX@'+aMID+'{'+aSubject+'}',
                                                            '',
                                                            nil,
                                                            ACICON_MAILNEW);
                                  aTreeEntry := TREE_ID_MESSAGES;
                                  inc(NewMessages);
                                  Data.Users.History.AddItemWithoutUser(Customers.DataSet,Format(strActionMessageReceived,[aSubject]),
                                                                'MESSAGEIDX@'+aMID+'{'+aSubject+'}',
                                                                '',
                                                                nil,
                                                                ACICON_MAILNEW);
                                end
                              else
                                begin
                                  aTreeEntry := TREE_ID_UNKNOWN_MESSAGES;
                                  inc(NewUnknownMessages);
                                end;
                              Customers.Free;
                              if aTreeEntry <> TREE_ID_MESSAGES then
                                begin
                                  if msg.Header.ToList.Count > 0 then
                                    if getemailaddr(trim(msg.Header.ToList[0])) = getemailaddr(trim(msg.Header.From)) then
                                      aTreeEntry := TREE_ID_SPAM_MESSAGES;
                                  if aTreeEntry = TREE_ID_UNKNOWN_MESSAGES then
                                    begin //Filter Spam
                                      SpamPoints := 0;
                                      b := 0;
                                      for a := 0 to msg.Header.CustomHeaders.Count-1 do
                                        begin
                                          atmp := msg.Header.CustomHeaders[a];
                                          if copy(atmp,0,9) = 'Received:' then
                                            begin
                                              inc(b);
                                              lSP := 2;
                                              atmp := copy(atmp,16,length(atmp));
                                              atmp := trim(copy(atmp,0,pos('by',lowercase(atmp))-1));
                                              if copy(atmp,0,1) = '[' then
                                                lSP := lSP+2;//kein DNS
                                              if (pos('with esmtps',lowercase(msg.Header.CustomHeaders[a]))>0)//verschlüsselte Verbindung
                                              or (pos('with local',lowercase(msg.Header.CustomHeaders[a]))>0)//lokal
                                              then
                                                lSP := 0;
                                            end
                                          else if copy(atmp,0,17)='List-Unsubscribe:' then
                                            lSP := lSP+2;//Alle Spammer versuchen sich als Mailingliste auszugeben
                                                         //und pber den List-Unsubscribe nen Button einzublenden "zum abbestellen"
                                        end;
                                      a := 0;
                                      if msg.Header.FindHeader('X-Spam-Flag') = 'YES' then
                                        SpamPoints := SpamPoints+4;
                                      if  (msg.Header.FindHeader('X-GMX-Antispam') <> '') then
                                        begin
                                          if TryStrToInt(trim(copy(trim(msg.Header.FindHeader('X-GMX-Antispam')),0,pos(' ',trim(msg.Header.FindHeader('X-GMX-Antispam')))-1)),a) then
                                            if a > 0 then
                                              SpamPoints := SpamPoints+4;
                                        end;
                                      atmp := trim(msg.Header.From);
                                      if (pos('>',atmp) > 0) and (pos('<',atmp) > 0) then
                                        atmp := getemailaddr(atmp)
                                      else if atmp = '' then
                                        SpamPoints := SpamPoints+4   //Kein Absender
                                      else
                                        SpamPoints := SpamPoints+1; //Kein Realname
                                      //Mails mit großer Empfängeranzahl
                                      SpamPoints := SpamPoints+msg.Header.ToList.Count*0.5;
                                    end;
                                  if ExecRegExpr('([0-9]{1,3}(\-|\.)[0-9]{1,3}(\-|\.)[0-9]{1,3}(\-|\.)[0-9]{1,3}.+[a-z0-9]+\.[a-z0-9]{2,6})',msg.Header.CustomHeaders.Text) then
                                    SpamPoints+=2;//dynamische IP
                                  atmp := trim(msg.Header.From);
                                  if (SpamPoints>0) and (Spampoints<=3) then
                                    begin
                                      if (pos('>',atmp) > 0) and (pos('<',atmp) > 0) then
                                        atmp := getemailaddr(atmp);
                                      aChk := mailcheck(atmp);
                                      case aChk of
                                      1,2,3: aChk := 0;
                                      end;
                                      SpamPoints+=aChk;
                                    end;
                                  if SpamPoints > 3 then
                                    begin
                                      aTreeEntry := TREE_ID_SPAM_MESSAGES;
                                    end;
                                end;
                              if pop.Retr(MID) then //Naricht holen
                                begin
                                  Message.Select(0);
                                  Message.Open;
                                  with Message.DataSet do
                                    begin //Messagenot there
                                      BMID := Data.GetUniID(nil);
                                      Insert;
                                      FieldByName('USER').AsString := Data.Users.DataSet.FieldByName('ACCOUNTNO').AsString;
                                      FieldByName('ID').AsString := aMID;
                                      FieldByName('MSG_ID').AsInteger:=BMID;
                                      FieldByName('TYPE').AsString := 'EMAIL';
                                      FieldByName('READ').AsString := 'N';
                                      fullmsg := TMimeMess.Create;
                                      fullmsg.Lines.Text:=pop.FullResult.Text;
                                      fullmsg.DecodeMessage;
                                      Message.DecodeMessage(fullmsg);
                                      fullmsg.Free;
                                      FieldByName('TREEENTRY').AsInteger := aTreeEntry;
                                      if aTreeEntry = TREE_ID_SPAM_MESSAGES then
                                        FieldByName('READ').AsString := 'Y';
                                      Post;
                                      MessageHandler.SendCommand('prometerp','Message.refresh');
                                    end;
                                  if DoArchive and Assigned(pop.FullResult) then
                                    begin
                                      ArchiveMsg := TArchivedMessage.Create(nil,Data);
                                      ArchiveMsg.CreateTable;
                                      ArchiveMsg.Insert;
                                      ArchiveMsg.DataSet.FieldByName('ID').AsString:=aMID;
                                      ss := TStringStream.Create(pop.FullResult.Text);
                                      Data.StreamToBlobField(ss,ArchiveMsg.DataSet,'DATA');
                                      ss.Free;
                                      ArchiveMsg.DataSet.Post;
                                      if DoDelete then
                                        begin
                                          pop.Dele(MID);
                                        end;
                                      ArchiveMsg.Free;
                                    end
                                  else if DoDelete then
                                    pop.Dele(MID);
                                end
                              else
                                begin
                                  ReplaceOMailAccounts := False;
                                  break;
                                end;
                            end
                          else
                            begin
                              if DoArchive then
                                begin
                                  if pop.Retr(MID) then //Naricht holen
                                    begin
                                      ArchiveMsg := TArchivedMessage.Create(nil,Data);
                                      ArchiveMsg.CreateTable;
                                      ArchiveMsg.Insert;
                                      ArchiveMsg.DataSet.FieldByName('ID').AsString:=aMID;
                                      ss := TStringStream.Create(pop.FullResult.Text);
                                      Data.StreamToBlobField(ss,ArchiveMsg.DataSet,'DATA');
                                      ss.Free;
                                      ArchiveMsg.DataSet.Post;
                                      if DoDelete then
                                        begin
                                          pop.Dele(MID);
                                        end;
                                      ArchiveMsg.Free;
                                    end;
                                end
                              else if DoDelete then
                                pop.Dele(MID);
                            end;
                          msg.Free;
                        end;
                    except
                      ReplaceOMailAccounts := False;
                      break;
                    end;
                  end;
                pop.Logout;
                MList.Free;
               end
             else
               begin
                 if pop.ResultString = '' then
                   writemessage(strMailLoginFailed)
                 else
                   writemessage(pop.ResultString);
               end;
             pop.Free;
             omailaccounts := omailaccounts+'|';
           end
         else
           omailaccounts := omailaccounts+copy(mailaccounts,0,pos('|',mailaccounts));
         mailaccounts := copy(mailaccounts,pos('|',mailaccounts)+1,length(mailaccounts));
       end;
  if ReplaceOmailaccounts then
    begin
      with Self as IBaseDbInterface do
        DBConfig.WriteString('MAILACCOUNTS',omailaccounts);
    end;
  MessageIndex.Free;
  DeletedItems.Free;
  Message.Free;
  aConnection.Free;
end;

function TPOP3Receiver.GetSingleInstance: Boolean;
begin
  Result:=True;
end;

constructor TPOP3Receiver.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
end;
function TPOP3Receiver.CommandReceived(Sender: TObject; aCommand: string
  ): Boolean;
var
  aUser: String;
begin
  Result := False;
  if copy(aCommand,0,8) = 'Receive(' then
    begin
      aUser := copy(aCommand,9,length(aCommand));
      aUser := copy(aUser,0,length(aUser)-1);
      ReceiveMails(aUser);
      Result := True;
    end;
end;
destructor TPOP3Receiver.Destroy;
begin
  inherited Destroy;
end;
var
  Application: TPOP3Receiver;
{$R *.res}
begin
  Application:=TPOP3Receiver.Create(nil);
  Application.Run;
  Application.Free;
end.
