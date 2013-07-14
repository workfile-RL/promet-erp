unit uAccountingFrame;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, types, FileUtil, LR_DBSet, Forms, Controls, uPrometFrames,
  uAccounting, db, uFilterFrame, Dialogs, uBaseDBInterface, DBGrids, Grids,
  Graphics, ActnList, ExtCtrls,Variants;
type

  { TfAccountingFrame }

  TfAccountingFrame = class(TPrometMainFrame)
    acOnlineUpdate: TAction;
    acFindTransaction: TAction;
    acSalesListPay: TAction;
    acCombineItems: TAction;
    acGotoVoucher: TAction;
    acPasteLinkasVoucher: TAction;
    acSingleLineView: TAction;
    ActionList1: TActionList;
    procedure acFindTransactionExecute(Sender: TObject);
    procedure acGotoVoucherExecute(Sender: TObject);
    procedure acOnlineUpdateExecute(Sender: TObject);
    procedure acPasteLinkasVoucherExecute(Sender: TObject);
    procedure acSingleLineViewExecute(Sender: TObject);
    procedure FListDrawColumnCell(Sender: TObject; const Rect: TRect;
      DataCol: Integer; Column: TColumn; State: TGridDrawState);
  private
    { private declarations }
    FList: TfFilter;
    FAccount : LargeInt;
    aFDS: TfrDBDataSet;
    aDS: TDataSource;
  public
    { public declarations }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy;override;
    function OpenFromLink(aLink : string) : Boolean;override;
    procedure SetLanguage;override;
    procedure OpenAccount(aID : LargeInt);
    property Account : LargeInt read FAccount;
  end;
implementation
uses uData,uAccountingQue,uBaseVisualControls,uBaseERPDBClasses,Utils,
  uIntfStrConsts,uBookAccounting,uPerson,uOrder,lconvencoding,
  uBaseVisualApplication, ClipBrd, uError, uMain, uFindTransaction;
{$R *.lfm}
resourcestring
  strTransactionEqualToorder    = 'Ist die Buchung:'+lineending+'%s'+lineending+'%s'+lineending+lineending+' deckungsgleich mit '+lineending+lineending+'%s'+lineending+'%s'+lineending+' ?';
procedure TfAccountingFrame.FListDrawColumnCell(Sender: TObject;
  const Rect: TRect; DataCol: Integer; Column: TColumn; State: TGridDrawState);
var
  aText: String;
  aTextStyle : TTextStyle = (Alignment:taLeftJustify;
                             Layout : tlTop;
                             SingleLine : False;
                             Clipping  : True;
                             ExpandTabs:False;
                             ShowPrefix:False;
                             Wordbreak:false;
                             Opaque:True;
                             SystemFont:False;
                             RightToLeft:False);
  aRect: TRect;
  tmp: String;
begin
  with (Sender as TDBGrid), Canvas do
    begin
      Canvas.FillRect(Rect);
      if gdSelected in State then
        Canvas.Font.Color:=clHighlightText
      else
        Canvas.Font.Color:=clWindowText;
      if Column.FieldName = 'VOUCHER' then
        begin
          if not TDBGrid(Sender).DataSource.DataSet.FieldByName('VOUCHER').IsNull then
            begin
              tmp := TDBGrid(Sender).DataSource.DataSet.FieldByName('VOUCHER').AsString;
              if copy(tmp,0,15) = 'ACCOUNTEXCHANGE' then
                fVisualControls.Images.Draw(TDBGrid(Sender).Canvas,Rect.Left,Rect.Top,52)
              else if copy(tmp,0,6) = 'ORDERS' then
                fVisualControls.Images.Draw(TDBGrid(Sender).Canvas,Rect.Left,Rect.Top,25);
            end;
        end
      else if Column.FieldName = 'PURPOSE' then
        begin
          aText := Column.Field.AsString;
          aRect := Rect;
          TextRect(aRect,aRect.Left+3,Rect.Top,aText,aTextStyle);
          dec(aRect.Right,1);
          dec(aRect.Bottom,1);
          if (gdFocused in State) and (not TDBGrid(Sender).EditorMode) then
            TDBGrid(Sender).Canvas.DrawFocusRect(arect);
        end
      else
        DefaultDrawColumnCell(Rect, DataCol, Column, State);
      end;
end;
procedure TfAccountingFrame.acOnlineUpdateExecute(Sender: TObject);
begin
  fAccountingQue.Setlanguage;
  fAccountingQue.Intf.Addrequest(DataSet.FieldByName('SORTCODE').AsString,DataSet.FieldByName('ACCOUNTNO').AsString);
end;

procedure TfAccountingFrame.acPasteLinkasVoucherExecute(Sender: TObject);
var
  Stream: TStringStream;
  aLinks: String;
  aLink: String;
  aLink2: string;
begin
  Stream := TStringStream.Create('');
  if Clipboard.GetFormat(LinkClipboardFormat,Stream) then
    begin
      Stream.Position:=0;
      aLinks := Stream.DataString;
    end
  else
    fError.ShowWarning(strCantgetClipboardContents);
  Stream.Free;
  if pos(';',aLinks) > 0 then
    begin
      aLink := copy(aLinks,0,pos(';',aLinks)-1);
      TAccounts(DataSet).Exchange.DataSet.Edit;
      TAccounts(DataSet).Exchange.FieldByName('VOUCHER').AsString := aLink;
      TAccounts(DataSet).Exchange.DataSet.Post;
      if copy(aLink,0,pos('@',aLink)-1) = 'ACCOUNTEXCHANGE' then
        begin
          aLink2 := Data.BuildLink(TAccounts(DataSet).Exchange.DataSet);
          if Data.GotoLink(aLink) then
            begin
              Application.ProcessMessages;
              if  (fMain.pcPages.ActivePage.ControlCount > 0)
              and (fMain.pcPages.ActivePage.Controls[0] is TfAccountingFrame)
              then
                begin
                  TAccounts(TfAccountingFrame(fMain.pcPages.ActivePage.Controls[0]).DataSet).Exchange.DataSet.Edit;
                  TAccounts(TfAccountingFrame(fMain.pcPages.ActivePage.Controls[0]).DataSet).Exchange.FieldByName('VOUCHER').AsString := aLink2;
                  TAccounts(TfAccountingFrame(fMain.pcPages.ActivePage.Controls[0]).DataSet).Exchange.DataSet.Post;
                end;
            end;
        end;
    end;
end;
procedure TfAccountingFrame.acSingleLineViewExecute(Sender: TObject);
var
  lines: Integer;
  tmp: TBitmap;
begin
  if acSingleLineView.Checked then
    lines := 1
  else lines := 4;
  tmp := TBitmap.Create;
  FList.gList.DefaultRowHeight:=lines*(tmp.Canvas.TextExtent('ABW').cy+2);
  tmp.Free;
end;
procedure TfAccountingFrame.acFindTransactionExecute(Sender: TObject);
begin
  fFindTransaction.Execute(TAccountExchange(FList.DataSet));
end;
procedure TfAccountingFrame.acGotoVoucherExecute(Sender: TObject);
begin
  Data.GotoLink(TAccounts(DataSet).Exchange.FieldByName('VOUCHER').AsString);
end;
constructor TfAccountingFrame.Create(AOwner: TComponent);
var
  tmp: TBitmap;
begin
  inherited Create(AOwner);
  Dataset := TAccounts.Create(nil,Data);
  FList := TfFilter.Create(Self);
  with FList do
    begin
      FilterType:='A';
      DefaultRows:='GLOBALWIDTH:965;CHECKED:50;VOUCHER:50;NAME:300;RSORTCODE:100;RACCOUNTNO:100;VALUE:70;CURRENCY:70;BALLANCE:100;VALUEDATE:100;';
      Parent := Self;
      Align := alClient;
      Show;
    end;
  acSingleLineViewExecute(nil);
  FList.DataSet := TAccounts(DataSet).Exchange;
  FList.gList.OnDrawColumnCell:=@FListDrawColumnCell;
  FList.AddToolbarAction(acOnlineupdate);
  FList.AddToolbarAction(acFindTransaction);
  FList.AddContextAction(acGotoVoucher);
  FList.AddContextAction(acPasteLinkAsVoucher);
  FList.AddToolbarToggle(acSingleLineView);
  aFDS := TfrDBDataSet.Create(FList);
  aFDS.Name:='DAccounts';
  aDS := TDataSource.Create(FList);
  aDS.DataSet := TAccounts(DataSet).DataSet;
  aDS.Name:='Accounts';
  aFDS.DataSource := aDS;

end;
destructor TfAccountingFrame.Destroy;
begin
  FList.DataSet := nil;
  if Assigned(FConnection) then
    begin
      CloseConnection;
      FConnection.Free;
    end;
  FList.Free;
  DataSet.Free;
  inherited Destroy;
end;
function TfAccountingFrame.OpenFromLink(aLink: string) : Boolean;
var
  ID: String;
  tmp1: String;
  tmp2: String;
begin
  if pos('{',aLink) > 0 then
    aLink := copy(aLink,0,pos('{',aLink)-1)
  else if rpos('(',aLink) > 0 then
    aLink := copy(aLink,0,rpos('(',aLink)-1);
  Result := False;
  ID := aLink;
  ID   := copy(ID, pos('@', ID) + 1, length(ID));
  tmp1 := copy(ID, 0, pos('&&', ID) - 1);
  ID   := copy(ID, pos('&&', ID) + 2, length(ID));
  tmp2 := ID;
  DataSet.Open;
  TAccounts(DataSet).Exchange.Open;
  if Data.Locate(DataSet,'SQL_ID',tmp1,[]) then
    begin
      OpenAccount(StrToInt(tmp1));
      if not TAccounts(DataSet).Exchange.DataSet.Locate('SQL_ID',tmp2,[]) then
        begin
          Data.SetFilter(TAccounts(DataSet).Exchange,Data.QuoteField('SQL_ID')+'='+Data.QuoteValue(tmp2),1,'','ASC',False,False);
          FList.AddFilter('DATE',TAccounts(DataSet).Exchange.FieldByName('DATE').AsString);
          Data.SetFilter(TAccounts(DataSet).Exchange,'',0,'','ASC',False,False);
          Result := Data.Locate(TAccounts(DataSet).Exchange,'SQL_ID',tmp2,[]);
        end
      else
        begin
          Result := True;
        end;
      if Result then FList.SetActive;
    end;
end;
procedure TfAccountingFrame.SetLanguage;
begin
end;
procedure TfAccountingFrame.OpenAccount(aID: LargeInt);
begin
  Data.SetFilter(DataSet,Data.QuoteField('SQL_ID')+'='+Data.QuoteValue(IntToStr(aID)));
  DataSet.Open;
  if DataSet.Count > 0 then
    begin
      TabCaption := TAccounts(DataSet).FieldByName('NAME').AsString;
      FList.SortField:='VALUEDATE';
      FList.SortDirection:=sdDescending;
      FList.acFilter.Execute;
      FAccount := aID;
    end;
  FList.SetActive;
end;
end.

