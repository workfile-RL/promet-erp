{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit pcalendar;

interface

uses
  uCalendarFrame, uEventEdit, LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('pcalendar', @Register);
end.
