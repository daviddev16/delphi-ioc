unit IoC;

interface

uses
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  System.SysUtils;

type
  EIoCException = class(Exception);
  EIoCBeanNotFoundException = class(EIoCException);

  ESingletonNotFoundException = class(EIoCBeanNotFoundException);

  TIdentityHelper = record
    public
      class function Make(const TypeInfo: PTypeInfo): String;
        overload; static; inline;

      class function Make(const TypeInfo: PTypeInfo; const Qualifier: String): String;
        overload; static; inline;
    end;

  TBean = record
    strict private
      FValue: TValue;
    public
      function Unwrap<T>(): T;
      procedure Close();
      class operator Finalize(var Dest: TBean);
    public
      constructor Create(const Value: TValue);
    end;

  TBeanHashTable = TDictionary<String, TBean>;

  ISingletonBeanContainer = interface
    function TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
  end;


  IBeanFactory = interface
    function CreateBean(const Identity: String): TBean;
  end;

  IBeanContainer = interface(ISingletonBeanContainer)
    function TryGetScoped(const Identity: String; out Bean: TBean): Boolean;
    function TryGetTransient(const Identity: String; out Bean: TBean): Boolean;
    function TryGetAny(const Identity: String; out Bean: TBean): Boolean;
  end;

  TSessionBeanContainer = class;
  TSingletonBeanContainerHolder = class;

  TFactoryContext = class
    strict private
      FBeanContainer: TSessionBeanContainer;
    public
      function AnyScoped<T>(): T;
      function AnySingleton<T>(): T;
      function Any<T>(): T;
    end;

  TSessionBeanContainer = class(TInterfacedObject, IBeanContainer, IBeanFactory)
    strict private
      FScopedTable: TBeanHashTable;
      FTransientTable: TBeanHashTable;
    protected // internal interfaces
      function CreateBean(const Identity: String): TBean;
      function TryGetScoped(const Identity: String; out Bean: TBean): Boolean;
      function TryGetTransient(const Identity: String; out Bean: TBean): Boolean;
      function TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
      function TryGetAny(const Identity: String; out Bean: TBean): Boolean;
    public // public interfaces
      function GetScoped<T>(): T; overload;
      function GetScoped<T>(const Qualifier: String): T; overload;
      function GetAny<T>(): T; overload;
      function GetAny<T>(const Qualifier: String): T; overload;
      function GetSingleton<T>(): T; overload;
      function GetSingleton<T>(const Qualifier: String): T; overload;
      function GetTransient<T>(): T; overload;
      function GetTransient<T>(const Qualifier: String): T; overload;
    public
      constructor Create();
      destructor Destroy(); override;
    end;

  TSingletonBeanContainerHolder = class
    strict private
      class var FSingletonBeanContainer: IBeanContainer;
    public
      class function TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
      class constructor Initialize();
      class destructor Unitialize();
    end;

implementation


{ TSessionBeanContainer }

constructor TSessionBeanContainer.Create();
begin
  FScopedTable := TBeanHashTable.Create();
  FTransientTable := TBeanHashTable.Create();
end;

function TSessionBeanContainer.GetScoped<T>: T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  if not TryGetScoped(lIdentity, lBean) then
  begin
    lBean := CreateBean(lIdentity);
    FScopedTable.AddOrSetValue(lIdentity, lBean);
  end;

  Result := lBean.Unwrap<T>();
end;

function TSessionBeanContainer.GetAny<T>(const Qualifier: String): T;
begin

end;

function TSessionBeanContainer.GetAny<T>(): T;
begin

end;

function TSessionBeanContainer.GetScoped<T>(const Qualifier: String): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  if not TryGetScoped(lIdentity, lBean) then
  begin
    lBean := CreateBean(lIdentity);
    FScopedTable.AddOrSetValue(lIdentity, lBean);
  end;

  Result := lBean.Unwrap<T>();
end;

function TSessionBeanContainer.GetSingleton<T>(): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T));

  if TryGetSingleton(lIdentity, lBean) then
    Exit;

  raise ESingletonNotFoundException.Create(lIdentity);
end;

function TSessionBeanContainer.GetSingleton<T>(const Qualifier: String): T;
var
  lBean: TBean;
  lIdentity: String;
begin
  lIdentity := TIdentityHelper.Make(TypeInfo(T), Qualifier);

  if TryGetSingleton(lIdentity, lBean) then
    Exit;

  raise ESingletonNotFoundException.Create(lIdentity);
end;

function TSessionBeanContainer.GetTransient<T>: T;
begin

end;

function TSessionBeanContainer.GetTransient<T>(const Qualifier: String): T;
begin

end;

function TSessionBeanContainer.TryGetAny(const Identity: String; out Bean: TBean): Boolean;
begin
  if TryGetScoped(Identity, Bean) then
    Exit;

  if TryGetTransient(Identity, Bean) then
    Exit;

  if TryGetSingleton(Identity, Bean) then
    Exit;
end;

function TSessionBeanContainer.TryGetScoped(const Identity: String; out Bean: TBean): Boolean;
begin
  Result := FScopedTable.TryGetValue(Identity, Bean);
end;

function TSessionBeanContainer.TryGetSingleton(const Identity: String; out Bean: TBean): Boolean;
begin
  Result := TSingletonBeanContainerHolder.TryGetSingleton(Identity,Bean);
end;

function TSessionBeanContainer.TryGetTransient(const Identity: String; out Bean: TBean): Boolean;
begin
  Result := FTransientTable.TryGetValue(Identity, Bean);
end;

function TSessionBeanContainer.CreateBean(const Identity: String): TBean;
begin

end;

destructor TSessionBeanContainer.Destroy();
begin
  FreeAndNil(FScopedTable);
  FreeAndNil(FTransientTable);
  inherited;
end;

{ TIdentity }

class function TIdentityHelper.Make(const TypeInfo: PTypeInfo; const Qualifier: String): String;
begin
  Result := Format('%s [%s]', [String(TypeInfo.Name), Qualifier]);
end;

class function TIdentityHelper.Make(const TypeInfo: PTypeInfo): String;
begin
  Result := String(TypeInfo.Name);
end;

{ TSingletonBeanContainerHolder }

class constructor TSingletonBeanContainerHolder.Initialize();
begin
  FSingletonBeanContainer := TSessionBeanContainer.Create();
end;

class function TSingletonBeanContainerHolder.TryGetSingleton(
  const Identity: String;
  out Bean: TBean): Boolean;
begin
  Result := FSingletonBeanContainer.TryGetScoped(Identity, Bean);
end;

class destructor TSingletonBeanContainerHolder.Unitialize();
begin
  FSingletonBeanContainer := nil;
end;

{ TBean }

constructor TBean.Create(const Value: TValue);
begin
  FValue := Value;
end;

function TBean.Unwrap<T>(): T;
begin
  Result := FValue.AsType<T>();
end;

procedure TBean.Close();
begin

end;

class operator TBean.Finalize(var Dest: TBean);
begin
  Dest.Close();
end;

{ TFactoryContext }

function TFactoryContext.Any<T>(): T;
begin
  Result := FBeanContainer.GetAny<T>();
end;

function TFactoryContext.AnyScoped<T>: T;
begin
  Result := FBeanContainer.GetScoped<T>();
end;

function TFactoryContext.AnySingleton<T>: T;
begin
  Result := FBeanContainer.GetSingleton<T>();
end;


end.
