{*******************************************************************************
  Copyright (C) Christian Ulrich info@cu-tec.de

  This source is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation; either version 2 of the License, or commercial alternative
  contact us for more information

  This code is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
  details.

  A copy of the GNU General Public License is available on the World Wide Web
  at <http://www.gnu.org/copyleft/gpl.html>. You can also obtain it by writing
  to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
  MA 02111-1307, USA.
Created 28.03.2017
*******************************************************************************}
unit upconfigurationserver;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, uappserverhttp,uAppServer, uData;

implementation

uses uBaseApplication,uBaseDBInterface,uIntfStrConsts,uEncrypt;

function HandleConfigRequest(Sender : TAppNetworkThrd;Method, URL: string;Headers : TStringList;Input,Output : TMemoryStream): Integer;
var
  i: Integer;
  aParameters: TStringList;
  s: String;
  tmp: String;
  aResult: TStringList;
  aType: String;
  aServer: String;
  aPW: String;
  aUser: String;
  aOptions: String;
  aDB: String;
begin
  Result := 500;
  aParameters := TStringList.Create;
  aResult := TStringList.Create;
  if pos('?',Url)>0 then
    Url := copy(URL,0,pos('?',Url)-1);
  try
    aParameters.Clear;
    for i := 0 to Headers.Count-1 do
      begin
        s := Headers[i];
        tmp := copy(s,0,pos(':',s)-1);
        aParameters.Add(lowercase(tmp)+':'+trim(copy(s,pos(':',s)+1,length(s))));
      end;
    if copy(lowercase(url),0,15)='/configuration/' then
      begin
        headers.Clear;
        Headers.Add('Access-Control-Allow-Origin: *');
        Headers.Add('Access-Control-Allow-Methods: GET, OPTIONS, POST');
        Headers.Add('Access-Control-Allow-Headers: Authorization,X-Requested-With');
        Url := copy(url,16,length(url));
        if lowercase(url) = 'add' then
          begin
            if lowercase(Method) = 'options' then
              Result := 200
            else
              begin
                Result := 500;
                Input.Position:=0;
                aResult.LoadFromStream(Input);
                if pos(':',aResult.Text)>0 then
                  begin
                    tmp := copy(aResult.Text,pos(':',aResult.Text)+1,length(aResult.Text));
                    aType := copy(tmp,0,pos(';',tmp)-1);
                    tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
                    aServer := copy(tmp,0,pos(';',tmp)-1);
                    tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
                    aDB := copy(tmp,0,pos(';',tmp)-1);
                    tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
                    aUser := copy(tmp,0,pos(';',tmp)-1);
                    tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
                    aPW := copy(tmp,0,pos(';',tmp)-1);
                    tmp := copy(tmp,pos(';',tmp)+1,length(tmp));
                    aOptions := tmp;
                    Result := 503;
                    aResult.Clear;
                    //TODO:check if DB Connection works
                    with BaseApplication as IBaseDbInterface,BaseApplication as  IBaseApplication do
                      begin
                        aResult.Clear;
                        aResult.Add('SQL');
                        aResult.Add(aType+';'+aServer+';'+aDB+';'+aUser+';'+Encrypt(aPW,99998));
                        aResult.SaveToFile(GetOurConfigDir+'standard.perml');
                        aResult.Clear;
                        Info('loading mandants...');
                        if not LoadMandants then
                          begin
                            Error(strFailedtoLoadMandants);
                            DeleteFile(GetOurConfigDir+'standard.perml');
                          end
                        else
                          begin
                            if DBLogin('standard','') then
                              begin
                                Result := 200;
                                uData.Data := GetDB;
                              end
                            else
                              begin
                                Result := 403;
                                aResult.Text := LastError;
                                aresult.SaveToStream(Output);
                                Output.Position:=0;
                                DeleteFile(GetOurConfigDir+'standard.perml');
                              end;
                          end;
                      end;
                  end;
              end;
          end
        else if lowercase(url) = 'status' then
          begin
            if Assigned(uData.Data) then
              Result := 403
            else
              Result := 200;
          end;
      end;
  except
    Result:=500;
  end;
  aResult.Free;
  aParameters.Free;
end;

{ TPrometWebDAVMaster }

initialization
  uappserverhttp.RegisterHTTPHandler(@HandleConfigRequest);

end.

