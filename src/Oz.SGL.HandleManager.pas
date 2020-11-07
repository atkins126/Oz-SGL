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

unit Oz.SGL.HandleManager;

interface

{$Region 'Uses'}

uses
  System.SysUtils, System.Math;

{$EndRegion}

{$T+}

{$Region 'Handles'}

type
  // Type handle
  hType = record
  const
    MaxIndex = 255;
  type
    TIndex = 0 .. MaxIndex; // 8 bits
  var
    v: TIndex;
  end;

  // Shared memory region handle
  hRegion = record
  const
    MaxIndex = 4095;
  type
    TIndex = 0 .. MaxIndex; // 12 bits
  var
    v: Cardinal;
  public
    function Index: TIndex; inline;
    // Type handle
    function Typ: hType; inline;
  end;

  // Collection handle
  hCollection = record
  const
    MaxIndex = 4095;
  type
    TIndex = 0 .. MaxIndex; // 12 bits
  var
    v: Cardinal;
  public
    constructor From(index: TIndex; region: hRegion);
    function Index: TIndex; inline;
    // Shared memory region handle
    function Region: hRegion; inline;
    // Type handle
    function Typ: hType; inline;
  end;

{$EndRegion}

{$Region 'TsgHandleManager: Handle manager'}

  TsgHandleManager = record
  const
    MaxNodes = 4095;
  type
    TIndex = 0 .. MaxNodes;
    TNode = record
      private
        procedure SetActive(const Value: Boolean);
        procedure SetEol(const Value: Boolean);
        procedure SetNext(const Value: TIndex);
        procedure SetPrev(const Value: TIndex);
        function GetActive: Boolean;
        function GetEol: Boolean;
        function GetNext: TIndex;
        function GetPrev: TIndex;
      public
        ptr: Pointer;
        v: Cardinal;
        property next: TIndex read GetNext write SetNext;
        property prev: TIndex read GetPrev write SetPrev;
        property active: Boolean read GetActive write SetActive;
        property eol: Boolean read GetEol write SetEol;
    end;
    PNode = ^TNode;
    TNodes = array [TIndex] of TNode;
  private
    FNodes: TNodes;
    FCount: Integer;
    FRegion: hRegion;
    FUsed: TIndex;
    FAvail: TIndex;
  public
    procedure Init(region: hRegion);
    function Add(p: Pointer): hCollection;
    procedure Update(handle: hCollection; p: Pointer);
    procedure Remove(handle: hCollection);
    function Get(handle: hCollection): Pointer;
    property Count: Integer read FCount;
  end;

{$EndRegion}

implementation

{$Region 'hRegion'}

function hRegion.Index: TIndex;
begin
  Result := v and $FFF;
end;

function hRegion.Typ: hType;
begin
  Result.v := (v shr 12) and $FF;
end;

{$EndRegion}

{$Region 'hCollection'}

constructor hCollection.From(index: TIndex; region: hRegion);
begin
  v := (region.v shl 14) or index;
end;

function hCollection.Index: TIndex;
begin
  // 2^12 - 1
  Result := v and $FFF;
end;

function hCollection.Region: hRegion;
begin
  // 2^8 + 2^12
  Result.v := v shr 12 and $FFFFF;
end;

function hCollection.Typ: hType;
begin
  // 2^8 0..255
  Result.v := (v shr 24) and $FF;
end;

{$EndRegion}

{$Region 'TsgHandleManager.TNode'}

function TsgHandleManager.TNode.GetNext: TIndex;
begin
  Result := v and $FFF;
end;

procedure TsgHandleManager.TNode.SetNext(const Value: TIndex);
begin
  v := v or (Ord(Value) and $FFF);
end;

function TsgHandleManager.TNode.GetPrev: TIndex;
begin
  Result := (v shr 12) and $FFF;
end;

procedure TsgHandleManager.TNode.SetPrev(const Value: TIndex);
begin
  v := v or ((Ord(Value) and $FFF) shl 12);
end;

function TsgHandleManager.TNode.GetActive: Boolean;
begin
  Result := False;
  if v and $80000000 <> 0 then
    Result := True;
end;

procedure TsgHandleManager.TNode.SetActive(const Value: Boolean);
begin
  if Value then
    v := v or $80000000
  else
    v := v and not $80000000;
end;

function TsgHandleManager.TNode.GetEol: Boolean;
begin
  Result := False;
  if v and $40000000 <> 0 then
    Result := True;
end;

procedure TsgHandleManager.TNode.SetEol(const Value: Boolean);
begin
  if Value then
    v := v or $40000000
  else
    v := v and not $40000000;
end;

{$EndRegion}

{$Region 'TsgHandleManager'}

procedure TsgHandleManager.Init(region: hRegion);
begin
  FillChar(Self, sizeof(TsgHandleManager), 0);
  FRegion := region;
end;

function TsgHandleManager.Add(p: Pointer): hCollection;
var
  idx: Integer;
  n: PNode;
begin
  Assert(FCount < MaxNodes - 1);
  idx := FAvail;
  Assert(idx < MaxNodes);
  n := @FNodes[idx];
  Assert(not n.active and not n.eol);
  FAvail := n.next;
  n.next := 0;
  n.active := True;
  n.ptr := p;
  Inc(FCount);
  Result := hCollection.From(idx, FRegion);
end;

procedure TsgHandleManager.Update(handle: hCollection; p: Pointer);
var
  n: PNode;
begin
  n := @FNodes[handle.Index];
  Assert(n.active);
  n.ptr := p;
end;

procedure TsgHandleManager.Remove(handle: hCollection);
var
  idx: Integer;
  n: PNode;
begin
  idx := handle.Index;
  n := @FNodes[idx];
  Assert(n.active);
  n.next := FAvail;
  n.active := False;
  FAvail := idx;
  Dec(FCount);
end;

function TsgHandleManager.Get(handle: hCollection): Pointer;
var
  n: PNode;
begin
  n := @FNodes[handle.Index];
  if not n.active then exit(nil);
  Result := n.ptr;
end;

{$EndRegion}

end.

