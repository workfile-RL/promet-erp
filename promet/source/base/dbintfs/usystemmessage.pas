{*******************************************************************************
Dieser Sourcecode darf nicht ohne gültige Geheimhaltungsvereinbarung benutzt werden
und ohne gültigen Vertriebspartnervertrag weitergegeben werden.
You have no permission to use this Source without valid NDA
and copy it without valid distribution partner agreement
Christian Ulrich
info@cu-tec.de
Created 01.06.2006
*******************************************************************************}
unit uSystemMessage;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, uBaseDbInterface, uBaseDbClasses, db, uBaseApplication,
  Variants;
type
  TSystemCommands = class(TBaseDBDataSet)
  public
    procedure DefineFields(aDataSet : TDataSet);override;
  end;
  TSystemMessages = class(TBaseDBDataSet)
  public
    procedure DefineFields(aDataSet : TDataSet);override;
  end;
  TSystemMessageEvent = function(Sender : TObject;aMessage : string) : Boolean of Object;
  TSystemCommandEvent = function(Sender : TObject;aCommand : string) : Boolean of Object;
  TMessageHandler = class(TThread)
  private
    Data : TBaseDBModule;
    Connection : TComponent;
    aSleepTime : Integer;
    ExceptMessage : string;
    CommandHandlers : array of TSystemCommandEvent;
    FExit: TNotifyEvent;
    MessageHandlers : array of TSystemMessageEvent;
    SysCommands: TSystemCommands;
    SysMessages: TSystemMessages;
    procedure CommandThere;
    procedure MessageThere;
    procedure ShowException;
    procedure DoTerminate;
  public
    constructor Create(aData : TBaseDBModule);
    destructor Destroy;override;
    procedure Execute; override;
    property OnExit : TNotifyEvent read FExit write FExit;
    procedure RegisterCommandHandler(CommandHandler : TSystemCommandEvent);
    function SendCommand(Target,Command : string) : Boolean;
  end;
implementation
procedure TSystemMessages.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'SYSTEMMESSAGES';
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('AUTO_ID',ftAutoInc,0,True);
            Add('PROCESS_ID',ftLargeInt,0,True);
            Add('COMMAND_ID',ftLargeInt,0,True);
            Add('MESSAGE',ftMemo,0,False);
          end;
    end;
end;
procedure TSystemCommands.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'SYSTEMCOMMANDS';
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('AUTO_ID',ftAutoInc,0,True);
            Add('PROCESS_ID',ftLargeInt,0,True);
            Add('COMMAND',ftMemo,0,False);
          end;
    end;
end;
procedure TMessageHandler.CommandThere;
var
  Found: Boolean;
  i: Integer;
begin
  Found := False;
  for i := 0 to length(CommandHandlers)-1 do
    if CommandHandlers[i](Self,SysCommands.FieldByName('COMMAND').AsString) then
      begin
        Found := True;
        SysCommands.DataSet.Delete;
        break;
      end;
  if not Found then
    SysCommands.DataSet.Next;
end;
procedure TMessageHandler.MessageThere;
begin

end;
procedure TMessageHandler.ShowException;
begin
end;
procedure TMessageHandler.DoTerminate;
var
  i: Integer;
begin
  Data.IgnoreOpenRequests := True;
  for i := 0 to length(CommandHandlers)-1 do
    if CommandHandlers[i](Self,'ForcedShutdown') then
      break;
end;
constructor TMessageHandler.Create(aData : TBaseDBModule);
begin
  Data := aData;
  Connection := Data.GetNewConnection;
  FreeOnTerminate := True;
  aSleepTime := 12000;
  SysCommands := TSystemCommands.Create(nil,Data,Connection);
  SysCommands.CreateTable;
  Data.SetFilter(SysCommands,Data.QuoteField('PROCESS_ID')+'='+Data.QuoteValue(IntToStr(Data.SessionID)),5);
  SysMessages := TSystemMessages.Create(nil,Data,Connection);
  SysMessages.CreateTable;
  Data.SetFilter(SysMessages,Data.QuoteField('PROCESS_ID')+'='+Data.QuoteValue(IntToStr(Data.SessionID)),5);
  inherited Create(False);
end;

destructor TMessageHandler.Destroy;
begin
  {
  if not Terminated then
    begin
      Terminate;
      WaitFor;
    end;
  }
  inherited Destroy;
end;

procedure TMessageHandler.Execute;
var
  ResSleepTime: LongInt;
const
  MinsleepTime = 700;
  MaxSleepTime = 8000;
begin
  while not Terminated do
    begin
      if (not Assigned(SysCommands)) or (not Assigned(SysCommands.DataSet)) then break;
      try
        SysCommands.DataSet.Refresh;
      except
        on e : Exception do
          begin
            ExceptMessage := e.Message;
            Synchronize(@ShowException);
            if Assigned(FExit) then
              FExit(Self);
            Synchronize(@DoTerminate);
            break;
          end;
      end;
      if SysCommands.Count > 0 then
        begin
          with SysCommands.DataSet do
            begin
              First;
              while not EOF do
                begin
                  {$IFNDEF LCLnogui}
                  Synchronize(@CommandThere);
                  {$ELSE}
                  CommandThere;
                  {$ENDIF}
                end;
            end;
          aSleepTime := MinSleepTime;
        end
      else if aSleepTime < MaxSleepTime then
        inc(aSleepTime,100);
      ResSleepTime := aSleepTime;
      while ResSleepTime > 0 do
        begin
          if Terminated then break;
          sleep(100);
          dec(ResSleepTime,100);
        end;
    end;
  if Assigned(FExit) then
    FExit(Self);
  FreeAndNil(SysCommands);
  FreeAndNil(SysMessages);
  FreeAndNil(Connection);
end;

procedure TMessageHandler.RegisterCommandHandler(
  CommandHandler: TSystemCommandEvent);
begin
  Setlength(CommandHandlers,length(CommandHandlers)+1);
  Commandhandlers[length(CommandHandlers)-1] := CommandHandler;
end;
function TMessageHandler.SendCommand(Target, Command: string) : Boolean;
var
  SysCmd: TSystemCommands;
  Procs: TActiveUsers;
begin
  if not Assigned(Self) then exit;
  Procs := TActiveUsers.Create(nil,Data);
  SysCmd := TSystemCommands.Create(nil,Data);
  try
    with Procs.DataSet as IBaseDbFilter do
      Data.SetFilter(Procs,ProcessTerm(Data.QuoteField('CLIENT')+'='+Data.QuoteValue(Target)));
    Data.SetFilter(SysCmd,'');
    Procs.DataSet.First;
    while not Procs.DataSet.EOF do
      begin
        if not SysCmd.DataSet.Locate('PROCESS_ID,COMMAND',VarArrayOf([Procs.Id.AsString,Command]),[]) then
          begin
            SysCmd.DataSet.Append;
            SysCmd.FieldByName('PROCESS_ID').AsString:=Procs.FieldByName('SQL_ID').AsString;
            SysCmd.FieldByName('COMMAND').AsString:=Command;
            SysCmd.DataSet.Post;
          end;
        Procs.DataSet.Next;
      end;
  finally
    SysCmd.Free;
    Procs.Free;
  end;
end;
end.

