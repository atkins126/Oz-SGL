﻿(* Standard Generic Library (SGL) for Pascal
  * Copyright (c) 2020 Marat Shaimardanov
  *
  * Licensed under the Apache License, Version 2.0 (the "License");
  * you may not use this file except in compliance with the License.
  * You may obtain a copy of the License at
  *
  *      http://www.apache.org/licenses/LICENSE-2.0
  *
  * Unless required by applicable law or agreed to in writing, software
  * distributed under the License is distributed on an "AS IS" BASIS,
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  * See the License for the specific language governing permissions and
  * limitations under the License.
*)

unit Oz.SGL.Hash;

interface

{$Region 'Uses'}

uses
  System.SysUtils, System.Math, System.TypInfo, System.Variants, Oz.SGL.Heap;

{$EndRegion}

{$T+}

{$Region 'THashData'}

type

  THashKind = (hkMultiplicative, hkSHA1, hkSHA2, hkSHA5, hkMD5);

  TsgHash  = record
  type
    TUpdateProc = procedure(const key: PByte; Size: Cardinal);
    THashProc = function(const key: PByte; Size: Cardinal): Cardinal;
  private
    FDigest: Cardinal;
    FUpdate: TUpdateProc;
    FHash: THashProc;
  public
    class function From(kind: THashKind): TsgHash; static;
    procedure Reset(kind: THashKind);

    class function HashMultiplicative(const key: PByte; Size: Cardinal): Cardinal; static;
    class function ELFHash(const digest: Cardinal; const key: PByte;
      const Size: Integer): Cardinal; static;

    // Update the Hash with the provided bytes
    procedure Update(const key; Size: Cardinal); overload;
    procedure Update(const key: TBytes; Size: Cardinal = 0); overload; inline;
    procedure Update(const key: string); overload; inline;
    // Hash function
    property Hash: THashProc read FHash;
  end;

{$EndRegion}

{$Region 'TsgHasher: GetHash and Equals operation'}

  PComparer = ^TComparer;
  TComparer = record
    Equals: TEqualsFunc;
    Hash: THashProc;
  end;

  PsgHasher = ^TsgHasher;
  TsgHasher = record
  private
    FComparer: PComparer;
  public
    class function From(m: TsgItemMeta): TsgHasher; overload; static;
    class function From(const Comparer: TComparer): TsgHasher; overload; static;
    function Equals(a, b: Pointer): Boolean;
    function GetHash(k: Pointer): Integer;
  end;

{$EndRegion}

function CompareRawByteString(const Left, Right: RawByteString): Integer;

implementation

type
  TPS1 = string[1];
  TPS2 = string[2];
  TPS3 = string[3];

  TInfoFlags = set of (ifVariableSize, ifSelector);
  PTabInfo = ^TTabInfo;
  TTabInfo = record
    Flags: TInfoFlags;
    Data: Pointer;
  end;

  TSelectProc = function(info: PTypeInfo; size: Integer): PComparer;

function CompareRawByteString(const Left, Right: RawByteString): Integer;
var
  Len, LLen, RLen: Integer;
  LPtr, RPtr: PByte;
begin
  if Pointer(Left) = Pointer(Right) then
    Result := 0
  else if Pointer(Left) = nil then
    Result := 0 - PInteger(PByte(Right) - 4)^ // Length(Right)
  else if Pointer(Right) = nil then
    Result := PInteger(PByte(Left) - 4)^ // Length(Left)
  else
  begin
    Result := Integer(PByte(Left)^) - Integer(PByte(Right)^);
    if Result <> 0 then
      Exit;
    LLen := PInteger(PByte(Left) - 4)^ - 1;  // Length(Left);
    RLen := PInteger(PByte(Right) - 4)^ - 1; // Length(Right);
    Len := LLen;
    if Len > RLen then Len := RLen;
    LPtr := PByte(Left) + 1;
    RPtr := PByte(Right) + 1;
    while Len > 0 do
    begin
      Result := Integer(LPtr^) - Integer(RPtr^);
      if Result <> 0 then
        Exit;
      if Len = 1 then break;
      Result := Integer(LPtr[1]) - Integer(RPtr[1]);
      if Result <> 0 then
        Exit;
      Inc(LPtr, 2);
      Inc(RPtr, 2);
      Dec(Len, 2);
    end;
    Result := LLen - RLen;
  end;
end;

function EqualsByte(a, b: Pointer): Boolean;
begin
  Result := PByte(a)^ = PByte(b)^;
end;

function EqualsInt16(a, b: Pointer): Boolean;
begin
  Result := PWord(a)^ = PWord(b)^;
end;

function EqualsInt32(a, b: Pointer): Boolean;
begin
  Result := PInteger(a)^ = PInteger(b)^;
end;

function EqualsInt64(a, b: Pointer): Boolean;
begin
  Result := PInt64(a)^ = PInt64(b)^;
end;

function EqualsSingle(a, b: Pointer): Boolean;
begin
  Result := PSingle(a)^ = PSingle(b)^;
end;

function EqualsDouble(a, b: Pointer): Boolean;
begin
  Result := PDouble(a)^ = PDouble(b)^;
end;

function EqualsCurrency(a, b: Pointer): Boolean;
begin
  Result := PCurrency(a)^ = PCurrency(b)^;
end;

function EqualsComp(a, b: Pointer): Boolean;
begin
  Result := PComp(a)^ = PComp(b)^;
end;

function EqualsExtended(a, b: Pointer): Boolean;
begin
  Result := Extended(a^) = Extended(b^);
end;

function EqualsString(a, b: Pointer): Boolean;
begin
  Result := PString(a)^ = PString(b)^;
end;

function EqualsClass(a, b: Pointer): Boolean;
begin
  if TObject(a^) <> nil then
    Result := TObject(a^).Equals(TObject(b^))
  else if TObject(b^) <> nil then
    Result := TObject(b^).Equals(TObject(a^))
  else
    Result := True;
end;

function EqualsMethod(a, b: Pointer): Boolean;
begin
  Result := TMethod(a^) = TMethod(b^);
end;

function EqualsLString(a, b: Pointer): Boolean;
begin
  Result := CompareRawByteString(RawByteString(a^), RawByteString(b^)) = 0;
end;

function EqualsWString(a, b: Pointer): Boolean;
begin
  Result := WideString(a^) = WideString(b^);
end;

function EqualsUString(a, b: Pointer): Boolean;
begin
  Result := UnicodeString(a^) = UnicodeString(b^);
end;

function EqualsVariant(a, b: Pointer): Boolean;
var
  l, r: Variant;
begin
  l := PVariant(a)^;
  r := PVariant(b)^;
  Result := VarCompareValue(l, r) = vrEqual;
end;

function EqualsRecord(a, b: Pointer): Boolean;
begin
  Result := False;
end;

function EqualsPointer(a, b: Pointer): Boolean;
begin
  Result := False;
end;

function EqualsI8(a, b: Pointer): Boolean;
begin
  Result := False;
end;

function HashByte(const key: PByte): Cardinal;
begin
  Result := TsgHash.ELFHash(0, key, 1);
end;

function HashInt16(const key: PByte): Cardinal;
begin
  Result := TsgHash.ELFHash(0, key, 2);
end;

function HashInt32(const key: PByte): Cardinal;
begin
  Result := TsgHash.ELFHash(0, key, 4);
end;

function HashInt64(const key: PByte): Cardinal;
begin
  Result := TsgHash.ELFHash(0, key, 8);
end;

function HashSingle(const key: PByte): Cardinal;
var
  m: Extended;
  e: Integer;
begin
  // Denormalized floats and positive/negative 0.0 complicate things.
  Frexp(PSingle(key)^, m, e);
  if m = 0 then
    m := Abs(m);
  Result := TsgHash.ELFHash(0, key, sizeof(Extended));
  Result := TsgHash.ELFHash(Result, key, sizeof(Integer));
end;

function HashDouble(const key: PByte): Cardinal;
var
  m: Extended;
  e: Integer;
begin
  // Denormalized floats and positive/negative 0.0 complicate things.
  Frexp(PDouble(key)^, m, e);
  if m = 0 then
    m := Abs(m);
  Result := TsgHash.ELFHash(0, key, sizeof(Extended));
  Result := TsgHash.ELFHash(Result, key, sizeof(Integer));
end;

function HashExtended(const key: PByte): Cardinal;
var
  m: Extended;
  e: Integer;
begin
  // Denormalized floats and positive/negative 0.0 complicate things.
  Frexp(PExtended(key)^, m, e);
  if m = 0 then
    m := Abs(m);
  Result := TsgHash.ELFHash(0, key, sizeof(Extended));
  Result := TsgHash.ELFHash(Result, key, sizeof(Integer));
end;

function HashComp(const key: PByte): Cardinal;
begin
  Result := TsgHash.ELFHash(0, key, sizeof(Comp));
end;

function HashCurrency(const key: PByte): Cardinal;
begin
  Result := TsgHash.ELFHash(0, key, sizeof(Currency));
end;

function HashString(const key: PByte): Cardinal;
var
  s: string;
begin
  s := PString(key)^;
  Result := TsgHash.HashMultiplicative(key, Length(s));
end;

function HashClass(const key: PByte): Cardinal;
begin
end;

function HashMethod(const key: PByte): Cardinal;
begin
end;

function HashLString(const key: PByte): Cardinal;
begin
end;

function HashWString(const key: PByte): Cardinal;
begin
end;

function HashUString(const key: PByte): Cardinal;
begin
end;

function HashVariant(const key: PByte): Cardinal;
begin
end;

function HashRecord(const key: PByte): Cardinal;
begin
end;

function HashPointer(const key: PByte): Cardinal;
begin
end;

function HashI8(const key: PByte): Cardinal;
begin
end;

const
  // Integer
  EntryByte: TComparer = (Equals: EqualsByte; Hash: HashByte);
  EntryInt16: TComparer = (Equals: EqualsInt16; Hash: HashInt16);
  EntryInt32: TComparer = (Equals: EqualsInt32; Hash: HashInt32);
  EntryInt64: TComparer = (Equals: EqualsInt64; Hash: HashInt64);
  // Real
  EntryR4: TComparer = (Equals: EqualsSingle; Hash: HashSingle);
  EntryR8: TComparer = (Equals: EqualsDouble; Hash: HashDouble);
  EntryR10: TComparer = (Equals: EqualsExtended; Hash: HashExtended);
  EntryRI8: TComparer = (Equals: EqualsComp; Hash: HashComp);
  EntryRC8: TComparer = (Equals: EqualsCurrency; Hash: HashCurrency);
  // String
  EntryString: TComparer = (Equals: EqualsString; Hash: HashString);

  EntryClass: TComparer = (Equals: EqualsClass; Hash: HashClass);
  EntryMethod: TComparer = (Equals: EqualsMethod; Hash: HashMethod);
  EntryLString: TComparer = (Equals: EqualsLString; Hash: HashLString);
  EntryWString: TComparer = (Equals: EqualsWString; Hash: HashWString);
  EntryVariant: TComparer = (Equals: EqualsVariant; Hash: HashVariant);
  EntryRecord: TComparer = (Equals: EqualsRecord; Hash: HashRecord);
  EntryPointer: TComparer = (Equals: EqualsPointer; Hash: HashPointer);
  EntryI8: TComparer = (Equals: EqualsI8; Hash: HashI8);
  EntryUString: TComparer = (Equals: EqualsUString; Hash: HashUString);

function SelectBinary(info: PTypeInfo; size: Integer): PComparer;
begin
  case size of
    1: Result := @EntryByte;
    2: Result := @EntryInt16;
    4: Result := @EntryInt32;
    8: Result := @EntryInt64;
    else
    begin
      System.Error(reRangeError);
      exit(nil);
    end;
  end;
end;

function SelectInteger(info: PTypeInfo; size: Integer): PComparer;
begin
  case GetTypeData(info)^.OrdType of
    otSByte, otUByte: Result := @EntryByte;
    otSWord, otUWord: Result := @EntryInt16;
    otSLong, otULong: Result := @EntryInt32;
  else
    System.Error(reRangeError);
    exit(nil);
  end;
end;

function SelectFloat(info: PTypeInfo; size: Integer): PComparer;
begin
  case GetTypeData(info)^.FloatType of
    ftSingle: Result := @EntryR4;
    ftDouble: Result := @EntryR8;
    ftExtended: Result := @EntryR10;
    ftComp: Result := @EntryRI8;
    ftCurr: Result := @EntryRC8;
  else
    System.Error(reRangeError);
    exit(nil);
  end;
end;

function SelectDynArray(info: PTypeInfo; size: Integer): PComparer;
begin
end;

const
  VTab: array [TTypeKind] of TTabInfo = (
    // tkUnknown
    (Flags: [ifSelector]; Data: @SelectBinary),
    // tkInteger
    (Flags: [ifSelector]; Data: @SelectInteger),
    // tkChar
    (Flags: [ifSelector]; Data: @SelectBinary),
    // tkEnumeration
    (Flags: [ifSelector]; Data: @SelectInteger),
    // tkFloat
    (Flags: [ifSelector]; Data: @SelectFloat),
    // tkString
    (Flags: []; Data: @EntryString),
    // tkSet
    (Flags: [ifSelector]; Data: @SelectBinary),
    // tkClass
    (Flags: []; Data: @EntryClass),
    // tkMethod
    (Flags: []; Data: @EntryMethod),
    // tkWChar
    (Flags: [ifSelector]; Data: @SelectBinary),
    // tkLString
    (Flags: []; Data: @EntryLString),
    // tkWString
    (Flags: []; Data: @EntryWString),
    // tkVariant
    (Flags: []; Data: @EntryVariant),
    // tkArray
    (Flags: [ifSelector]; Data: @SelectBinary),
    // tkRecord
    (Flags: [ifSelector]; Data: @EntryRecord),
    // tkInterface
    (Flags: []; Data: @EntryPointer),
    // tkInt64
    (Flags: []; Data: @EntryI8),
    // tkDynArray
    (Flags: [ifSelector]; Data: @SelectDynArray),
    // tkUString
    (Flags: []; Data: @EntryUString),
    // tkClassRef
    (Flags: []; Data: @EntryPointer),
    // tkPointer
    (Flags: []; Data: @EntryPointer),
    // tkProcedure
    (Flags: []; Data: @EntryPointer),
    // tkMRecord
    (Flags: [ifSelector]; Data: @EntryRecord));

{$Region 'TsgHash'}

class function TsgHash.From(kind: THashKind): TsgHash;
begin
  Result.Reset(kind);
end;

procedure TsgHash.Reset(kind: THashKind);
begin
  case kind of
    THashKind.hkMultiplicative:
      begin
        FHash := TsgHash.HashMultiplicative;
      end;
  end;
end;

procedure TsgHash.Update(const key; Size: Cardinal);
begin
  FUpdate(PByte(@key), Size);
end;

procedure TsgHash.Update(const key: TBytes; Size: Cardinal);
var
  L: Cardinal;
begin
  L := Size;
  if L = 0 then
    L := Length(key);
  FUpdate(PByte(key), L);
end;

procedure TsgHash.Update(const key: string);
begin
  Update(TEncoding.UTF8.GetBytes(key));
end;

class function TsgHash.HashMultiplicative(const key: PByte;
  Size: Cardinal): Cardinal;
var
  i, hash: Cardinal;
  p: PByte;
begin
  hash := 5381;
  p := key;
  for i := 1 to Size do
  begin
    hash := 33 * hash + p^;
    Inc(p);
  end;
  Result := hash;
end;

class function TsgHash.ELFHash(const digest: Cardinal; const key: PByte;
  const Size: Integer): Cardinal;
var
  i: Integer;
  p: PByte;
  t: Cardinal;
begin
  Result := digest;
  p := key;
  for i := 1 to Size do
  begin
    Result := (Result shl 4) + p^;
    Inc(p);
    t := Result and $F0000000;
    if t <> 0 then
      Result := Result xor (t shr 24);
    Result := Result and (not t);
  end;
end;

{$EndRegion}

{$Region 'TsgHasher'}

class function TsgHasher.From(m: TsgItemMeta): TsgHasher;
var
  info: PTabInfo;
begin
  if m.TypeInfo = nil then
    raise EsgError.Create('Invalid parameter');
  info := @VTab[PTypeInfo(m.TypeInfo)^.Kind];
  if ifSelector in info^.Flags then
    Result.FComparer := TSelectProc(info^.Data)(m.TypeInfo, m.ItemSize)
  else if info^.Data <> nil then
    Result.FComparer := PComparer(info^.Data)
  else
    raise EsgError.Create('TsgHasher: Type is not supported');
end;

class function TsgHasher.From(const Comparer: TComparer): TsgHasher;
begin
  Result.FComparer := @Comparer;
end;

function TsgHasher.Equals(a, b: Pointer): Boolean;
begin
  Result := PComparer(FComparer).Equals(a, b);
end;

function TsgHasher.GetHash(k: Pointer): Integer;
begin
  Result := PComparer(FComparer).Hash(k);
end;

{$EndRegion}

end.

