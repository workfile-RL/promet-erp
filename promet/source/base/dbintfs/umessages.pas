{*******************************************************************************
Dieser Sourcecode darf nicht ohne gültige Geheimhaltungsvereinbarung benutzt werden
und ohne gültigen Vertriebspartnervertrag weitergegeben werden.
You have no permission to use this Source without valid NDA
and copy it without valid distribution partner agreement
Christian Ulrich
info@cu-tec.de
Created 01.06.2006
*******************************************************************************}
unit uMessages;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, uBaseDbClasses, db, uBaseDBInterface, uDocuments,
  uBaseApplication, uBaseSearch, uIntfStrConsts,htmlconvert,LConvEncoding;
type

  { TMessageList }

  TMessageList = class(TBaseDBList)
  private
    function GetMsgID: TField;
  public
    procedure DefineFields(aDataSet : TDataSet);override;
    procedure SelectByID(aID : string);overload; //Select by ID
    procedure SelectByDir(aDir : Variant);
    procedure SelectByMsgID(aID : Int64);
    procedure SelectByParent(aParent : Variant);
    function GetTextFieldName: string;override;
    function GetNumberFieldName : string;override;
    procedure Delete;virtual;
    procedure Archive;
    procedure MarkAsRead;
    property MsgID : TField read GetMsgID;
  end;
  TMessageContent = class(TBaseDBDataSet)
  private
    FMessage: TMessageList;
    function GetText: string;
  public
    procedure DefineFields(aDataSet : TDataSet);override;
    procedure FillDefaults(aDataSet: TDataSet); override;
    procedure Select(aId : string);overload;
    property Message : TMessageList read FMessage write FMessage;
    property AsString : string read GetText;
  end;
  TMessage = class(TMessageList)
  private
    FDocuments: TDocuments;
    FMessageContent: TMessageContent;
    FSubMessages : TMessageList;
    function GetSubMessages: TMessageList;
  public
    constructor Create(aOwner : TComponent;DM : TComponent;aConnection : TComponent = nil;aMasterdata : TDataSet = nil);override;
    destructor Destroy;override;
    procedure Select(aID : Variant);override;
    procedure Open;override;
    procedure Delete;override;
    function CreateTable : Boolean;override;
    procedure FillDefaults(aDataSet : TDataSet);override;
    function BuildMessageID(aID : Variant) : string;
    property Content : TMessageContent read FMessageContent;
    property Documents : TDocuments read FDocuments;
    property SubMessages : TMessageList read GetSubMessages;
    procedure SelectFromLink(aLink: string); override;
    procedure Next; override;
    procedure Prior; override;
  end;
  TSpecialMessage = class(TMessage)
  public
    destructor Destroy;override;
  end;
  TArchivedMessage = class(TBaseDBDataSet)
  public
    procedure DefineFields(aDataSet : TDataSet);override;
  end;
implementation
uses uData,md5,Variants,Utils;
procedure TArchivedMessage.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'ARCHIVESTORE';
      TableCaption := strArchive;
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('ID',ftString,120,True);
            Add('DATA',ftBlob,0,False);
          end;
    end;
end;
destructor TSpecialMessage.Destroy;
begin
  inherited Destroy;
end;

function TMessageContent.GetText: string;
var
  sl: TStringList;
  ss: TStringStream;
  tmp: String;
begin
  sl := TStringList.Create;
  if UpperCase(FieldByName('DATATYP').AsString) = 'PLAIN' then
    begin
      ss := TStringStream.Create('');
      Data.BlobFieldToStream(DataSet,'DATA',ss);
      sl.Text:=HTMLDecode(ConvertEncoding(ss.DataString,GuessEncoding(ss.DataString),EncodingUTF8));
      sl.TextLineBreakStyle := tlbsCRLF;
      ss.Free;
    end
  else if UpperCase(FieldByName('DATATYP').AsString) = 'HTML' then
    begin
      ss:=TStringStream.Create('');
      Data.BlobFieldToStream(DataSet,'DATA',ss);
      ss.Position:=0;
      tmp := ss.DataString;
      tmp := HTMLToTxT(tmp);
      tmp := ConvertEncoding(tmp,GuessEncoding(tmp),EncodingUTF8);
      tmp := StringReplace(tmp, '&amp;'  ,'&', [rfreplaceall]);
      tmp := StringReplace(tmp, '&quot;' ,'"', [rfreplaceall]);
      tmp := StringReplace(tmp, '&lt;'   ,'<', [rfreplaceall]);
      tmp := StringReplace(tmp, '&gt;'   ,'>', [rfreplaceall]);
      tmp := StringReplace(tmp, '&nbsp;' ,' ', [rfreplaceall]);
      tmp := StringReplace(tmp, '&auml;' ,'ä', [rfreplaceall]);
      tmp := StringReplace(tmp, '&ouml;' ,'ö', [rfreplaceall]);
      tmp := StringReplace(tmp, '&uuml;' ,'ü', [rfreplaceall]);
      tmp := StringReplace(tmp, '&Auml;' ,'Ä', [rfreplaceall]);
      tmp := StringReplace(tmp, '&Ouml;' ,'Ö', [rfreplaceall]);
      tmp := StringReplace(tmp, '&Uuml;' ,'Ü', [rfreplaceall]);
      tmp := StringReplace(tmp, '&szlig;','ß', [rfreplaceall]);
      sl.Text:=tmp;
      ss.Free;
    end;
  Result := sl.Text;
  sl.Free;
end;

procedure TMessageContent.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'MESSAGES';
      TableCaption := strMessages;
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('ID',ftString,120,True);
            Add('RECEIVERS',ftMemo,0,False);
            Add('CC',ftMemo,0,False);
            Add('DATATYP',ftString,6,False);
            Add('REPLYTO',ftString,100,False);
            Add('HEADER',ftMemo,0,False);
            Add('DATA',ftBlob,0,False);
          end;
      if Assigned(ManagedIndexdefs) then
        with ManagedIndexDefs do
          begin
            Add('ID','ID',[]);
          end;
    end;
end;

procedure TMessageContent.FillDefaults(aDataSet: TDataSet);
begin
  inherited FillDefaults(aDataSet);
  DataSet.FieldByName('ID').AsVariant:=Message.FieldByName('ID').AsVariant;
  DataSet.FieldByName('DATATYP').AsString:='PLAIN';
end;
procedure TMessageContent.Select(aId: string);
begin
  with BaseApplication as IBaseDBInterface,DataSet as IBaseDBFilter, DataSet as IBaseManageDB do
      begin
        Filter :=QuoteField('ID')+'='+QuoteValue(aID);
        Limit := 1;
      end;
end;
function TMessage.GetSubMessages: TMessageList;
begin
  if not Assigned(FSubMessages) then
    begin
      FSubMessages := TMessageList.Create(Owner,DataModule,Connection);
      FSubmessages.SelectByParent(Self.Id.AsVariant);
    end;
  Result := FSubMessages;
end;
constructor TMessage.Create(aOwner: TComponent; DM: TComponent;
  aConnection: TComponent; aMasterdata: TDataSet);
begin
  inherited Create(aOwner, DM, aConnection, aMasterdata);
  FMessageContent := TMessageContent.Create(Owner,DM,aConnection);
  FMessageContent.Message := Self;
  FDocuments := TDocuments.Create(Owner,DM,aConnection);
  FSubMessages := nil;
end;
destructor TMessage.Destroy;
begin
  FreeAndNil(FSubMessages);
  FDocuments.Free;
  FMessageContent.Free;
  inherited Destroy;
end;
procedure TMessage.Select(aID: Variant);
begin
  inherited Select(aID);
  if aID <> Null then
    Documents.Select(aID);
  Content.Select('');
end;
procedure TMessage.Open;
begin
  inherited Open;
  Content.Select(DataSet.FieldbyName('ID').AsString);
end;
procedure TMessage.Delete;
var
  aDocument: TDocument;
  Found: Boolean;
begin
  if Count = 0 then exit;
  try
    Documents.Open;
    while Documents.Count > 0 do
      begin
        aDocument := TDocument.Create(Self,Data);
        aDocument.SelectByNumber(Documents.FieldByName('NUMBER').AsInteger);
        aDocument.Open;
        Found := False;
        while aDocument.Count > 0 do
          begin
            aDocument.DataSet.Delete;
            Found := True;
          end;
        aDocument.Free;
        Documents.DataSet.Refresh;
        if not Found then break;
      end;
  except
  end;
  Content.Open;
  while Content.Count > 0 do
    Content.DataSet.Delete;
  DataSet.Delete;
end;
function TMessage.CreateTable : Boolean;
begin
  Result := inherited CreateTable;
  Content.CreateTable;
end;
procedure TMessage.FillDefaults(aDataSet: TDataSet);
var
  tmpID: String;
  aGUID: TGUID;
begin
  with aDataSet,BaseApplication as IBaseDBInterface do
    begin
      FieldByName('TREEENTRY').AsVariant:=TREE_ID_MESSAGES;
      tmpID := '';
      CreateGUID(aGUID);
      tmpID := StringReplace(StringReplace(StringReplace(GUIDToString(aGUID),'-','',[rfReplaceAll]),'{','',[rfReplaceAll]),'}','',[rfReplaceAll]);
      FieldByName('ID').AsString:=tmpID+'@inv.local';
    end;
end;
function TMessage.BuildMessageID(aID: Variant): string;
begin

end;
procedure TMessage.SelectFromLink(aLink: string);
begin
  Select(0);
  if rpos('{',aLink) > 0 then
    aLink := copy(aLink,0,rpos('{',aLink)-1)
  else if rpos('(',aLink) > 0 then
    aLink := copy(aLink,0,rpos('(',aLink)-1);
  with DataSet as IBaseManageDB do
    if copy(aLink,0,pos('@',aLink)-1) = TableName then
      SelectByID(copy(aLink,pos('@',aLink)+1,length(aLink)));
end;
procedure TMessage.Next;
begin
  inherited Next;
  Content.Select(DataSet.FieldbyName('ID').AsString);
end;
procedure TMessage.Prior;
begin
  inherited Prior;
  Content.Select(DataSet.FieldbyName('ID').AsString);
end;

function TMessageList.GetMsgID: TField;
begin
  result := FieldByName('MSG_ID');
end;

procedure TMessageList.DefineFields(aDataSet: TDataSet);
begin
  with aDataSet as IBaseManageDB do
    begin
      TableName := 'MESSAGEIDX';
      TableCaption := strMessages;
      if Assigned(ManagedFieldDefs) then
        with ManagedFieldDefs do
          begin
            Add('USER',ftString,20,True);
            Add('ID',ftString,120,True);
            Add('TREEENTRY',ftLargeint,0,True);
            Add('MSG_ID',ftLargeint,0,True);
            Add('GRP_ID',ftLargeint,0,False);
            Add('TYPE',ftString,5,True);
            Add('READ',ftString,1,True);
            Add('SENDER',ftString,100,True);
            Add('RECEIVERS',ftMemo,0,False);
            Add('REPLYTO',ftMemo,0,False);
            Add('SENDDATE',ftDateTime,0,True);
            Add('ANSWERED',ftDateTime,0,False);
            Add('SUBJECT',ftString,220,false);
            Add('PARENT',ftLargeint,0,False);
            Add('LINES',ftInteger,0,False);
            Add('SIZE',ftLargeInt,0,False);
          end;
      if Assigned(ManagedIndexdefs) then
        with ManagedIndexDefs do
          begin
            Add('ID','ID',[]);
            Add('MSG_ID','MSG_ID',[]);
            Add('USER','USER',[]);
            Add('PARENT','PARENT',[]);
            Add('TREEENTRY','TREEENTRY',[]);
          end;
    end;
end;
procedure TMessageList.SelectByID(aID: string);
begin
  with BaseApplication as IBaseDBInterface do
    with DataSet as IBaseDBFilter do
      begin
        Filter := ProcessTerm(Data.QuoteField('ID')+'='+Data.QuoteValue(aID));
      end;
end;
procedure TMessageList.SelectByDir(aDir: Variant);
begin
  with BaseApplication as IBaseDBInterface do
    with DataSet as IBaseDBFilter do
      begin
        Filter := Data.QuoteField('TREEENTRY')+'='+Data.QuoteValue(VarToStr(aDir))+' AND '+ProcessTerm(Data.QuoteField('PARENT')+'='+Data.QuoteValue(''));
      end;
end;
procedure TMessageList.SelectByMsgID(aID: Int64);
begin
  with BaseApplication as IBaseDBInterface do
    with DataSet as IBaseDBFilter do
      begin
        Filter := Data.QuoteField('MSG_ID')+'='+Data.QuoteValue(IntToStr(aID));
      end;
end;
procedure TMessageList.SelectByParent(aParent: Variant);
begin
  with BaseApplication as IBaseDBInterface do
    with DataSet as IBaseDBFilter do
      begin
        Filter := Data.QuoteField('PARENT')+'='+Data.QuoteValue(IntToStr(aParent));
      end;
end;
function TMessageList.GetTextFieldName: string;
begin
  Result:='SUBJECT';
end;
function TMessageList.GetNumberFieldName: string;
begin
  Result:='MSG_ID';
end;
procedure TMessageList.Delete;
begin
  if Count = 0 then exit;
  DataSet.Edit;
  DataSet.FieldByName('TREEENTRY').AsVariant := TREE_ID_DELETED_MESSAGES;
  DataSet.FieldByName('READ').AsString := 'Y';
  DataSet.Post;
end;
procedure TMessageList.Archive;
begin
  if Count = 0 then exit;
  DataSet.Edit;
  DataSet.FieldByName('TREEENTRY').AsVariant := TREE_ID_ARCHIVE_MESSAGES;
  DataSet.FieldByName('READ').AsString := 'Y';
  DataSet.Post;
end;
procedure TMessageList.MarkAsRead;
begin
  if Count = 0 then exit;
  DataSet.Edit;
  DataSet.FieldByName('READ').AsString := 'Y';
  DataSet.Post;
end;
initialization
end.
