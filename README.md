# delphi-ioc

Uma biblioteca leve de **Inversão de Controle (IoC)** e **Injeção de Dependência (DI)** para Delphi, baseada em um modelo de fábrica com callbacks e suporte a três escopos de ciclo de vida de beans.

---

## Sumário

- [Conceitos](#conceitos)
- [Instalação](#instalação)
- [Início Rápido](#início-rápido)
- [Registrando Dependências](#registrando-dependências)
- [Escopos de Ciclo de Vida](#escopos-de-ciclo-de-vida)
  - [Scoped](#scoped)
  - [Singleton](#singleton)
  - [Transient](#transient)
  - [Any](#any)
- [Qualificadores](#qualificadores)
- [Injeção no Callback de Fábrica](#injeção-no-callback-de-fábrica)
- [Referência da API](#referência-da-api)
- [Limitações Técnicas](#limitações-técnicas)

---

## Conceitos

| Termo | Descrição |
|---|---|
| **Bean** | Qualquer objeto gerenciado pelo container IoC. |
| **Registry** | `TIoCRegistry` — onde os factories globais são registrados. |
| **Container** | `TSessionBeanContainer` — resolve e mantém beans em um escopo de sessão. |
| **Factory Callback** | Função anônima responsável por instanciar um bean. |
| **Identity** | Chave interna derivada do `TypeInfo` do tipo + qualificador opcional. |

---

## Instalação

Adicione `IoC.pas` ao seu projeto ou ao Search Path do Delphi. Não há dependências externas além da RTL padrão.

```
uses IoC;
```

---

## Início Rápido

O exemplo abaixo mostra o fluxo completo: registrar factories, criar um container de sessão e resolver uma dependência.

```delphi
program MeuApp;

{$APPTYPE CONSOLE}

uses
  IoC, Examples;

begin
  // 1. Registrar factories uma única vez na inicialização da aplicação
  TIoCRegistry
    .RegisterBeanFactory<IConnectionProvider>(
      function(Ctx: TBeanFactoryContext): TBeanValue
      begin
        Result := TConnectionProvider.Create();
      end)

    .RegisterBeanFactory<IProductRepository>(
      function(Ctx: TBeanFactoryContext): TBeanValue
      begin
        // Injeta IConnectionProvider como scoped dentro da mesma sessão
        Result := TProductRepository.Create(Ctx.AnyScoped<IConnectionProvider>());
      end);

  // 2. Criar um container por sessão/request
  var Container := TSessionBeanContainer.Create();
  try
    var Repo := Container.GetScoped<IProductRepository>();
    WriteLn('Total de produtos: ', Repo.Count());
  finally
    Container.Free();
  end;
end.
```

Saída esperada:

```
Called: TConnectionProvider.Create
Called: TProductRepository.Create
Total de produtos: 1000
Called: TProductRepository.Destroy
Called: TConnectionProvider.Create   <- destructor
```

---

## Registrando Dependências

Toda factory é registrada globalmente em `TIoCRegistry` antes de qualquer container ser criado.

```delphi
TIoCRegistry.RegisterBeanFactory<IMinhaInterface>(
  function(Ctx: TBeanFactoryContext): TBeanValue
  begin
    Result := TMinhaClasse.Create();
  end);
```

O registro é **encadeável** — `RegisterBeanFactory` retorna `TIoCRegistry`, permitindo múltiplos registros em uma única expressão:

```delphi
TIoCRegistry
  .RegisterBeanFactory<IServicoA>(factoryA)
  .RegisterBeanFactory<IServicoB>(factoryB)
  .RegisterBeanFactory<IServicoC>(factoryC);
```

---

## Escopos de Ciclo de Vida

### Scoped

O bean é criado na primeira resolução dentro de uma sessão e **reutilizado** em todas as resoluções subsequentes do mesmo container. Quando o container é destruído, as referências são liberadas.

```delphi
// Mesma instância dentro do Container
var A := Container.GetScoped<IMinhaInterface>();
var B := Container.GetScoped<IMinhaInterface>();
// A e B apontam para o mesmo objeto
```

**Ideal para:** conexões de banco de dados, contextos de unidade de trabalho (Unit of Work), objetos caros por request/sessão.

---

### Singleton

Beans singleton são mantidos em um container global compartilhado por toda a aplicação. Eles só podem ser pré-registrados via `TSessionBeanContainer` do singleton interno — **não** são criados automaticamente pelo container de sessão.

> ⚠️ A resolução via `GetSingleton<T>` lança `ESingletonNotFoundException` se o bean não tiver sido previamente registrado no container singleton global.

```delphi
// Resolver um singleton (deve ter sido registrado no container global)
var Cfg := Container.GetSingleton<IAppConfig>();
```

**Ideal para:** configurações globais, caches de aplicação, serviços sem estado.

---

### Transient

Um novo bean é **criado a cada resolução**. O container mantém internamente as referências para controle de ciclo de vida, mas cada chamada retorna uma instância diferente.

```delphi
var A := Container.GetTransient<IMinhaInterface>();
var B := Container.GetTransient<IMinhaInterface>();
// A e B são instâncias distintas
```

**Ideal para:** objetos leves, comandos, handlers de curta duração.

---

### Any

Resolve usando a política de precedência: **Scoped → Transient → Singleton**. Se não encontrar em nenhum escopo, cria um novo bean e o armazena como transient.

```delphi
var Svc := Container.GetAny<IMeuServico>();
```

---

## Qualificadores

Quando é necessário registrar múltiplas implementações de um mesmo tipo, use um qualificador string para diferenciar:

```delphi
// Registro
TIoCRegistry
  .RegisterBeanFactory<ILogger>('console',
    function(Ctx: TBeanFactoryContext): TBeanValue
    begin
      Result := TConsoleLogger.Create();
    end)

  .RegisterBeanFactory<ILogger>('file',
    function(Ctx: TBeanFactoryContext): TBeanValue
    begin
      Result := TFileLogger.Create();
    end);

// Resolução
var ConsoleLog := Container.GetScoped<ILogger>('console');
var FileLog    := Container.GetScoped<ILogger>('file');
```

---

## Injeção no Callback de Fábrica

O parâmetro `Ctx: TBeanFactoryContext` passado para cada callback permite resolver outras dependências do mesmo container durante a construção:

| Método | Comportamento |
|---|---|
| `Ctx.AnyScoped<T>()` | Resolve com escopo scoped (cria ou reutiliza do container da sessão). |
| `Ctx.AnySingleton<T>()` | Resolve apenas do container global singleton. |
| `Ctx.Any<T>()` | Resolve com política Any (Scoped → Transient → Singleton). |

```delphi
TIoCRegistry.RegisterBeanFactory<IServicoDeNegocio>(
  function(Ctx: TBeanFactoryContext): TBeanValue
  begin
    // IRepositorio e ILogger são resolvidos do mesmo container da sessão
    Result := TServicoDeNegocio.Create(
      Ctx.AnyScoped<IRepositorio>(),
      Ctx.AnyScoped<ILogger>()
    );
  end);
```

---

## Referência da API

### `TIoCRegistry`

| Método | Descrição |
|---|---|
| `RegisterBeanFactory<T>(Callback)` | Registra factory para o tipo `T`. |
| `RegisterBeanFactory<T>(Qualifier, Callback)` | Registra factory qualificada. |
| `GetDefaultBeanFactory()` | Retorna o `IBeanFactory` global padrão. |

### `TSessionBeanContainer`

| Método | Descrição |
|---|---|
| `GetScoped<T>()` | Resolve ou cria um bean scoped. |
| `GetScoped<T>(Qualifier)` | Idem com qualificador. |
| `GetTransient<T>()` | Resolve ou cria um bean transient. |
| `GetTransient<T>(Qualifier)` | Idem com qualificador. |
| `GetSingleton<T>()` | Resolve do container global; lança exceção se não encontrado. |
| `GetSingleton<T>(Qualifier)` | Idem com qualificador. |
| `GetAny<T>()` | Resolve com política Any. |
| `GetAny<T>(Qualifier)` | Idem com qualificador. |

### `TBean`

| Membro | Descrição |
|---|---|
| `Wrap(Value)` | Empacota um `TValue` como bean; lança `EBeanException` se vazio. |
| `Unwrap<T>()` | Extrai o valor tipado; suporta interfaces (`Supports`) e classes (cast RTTI). |
| `Close()` | Reservado para uso futuro (ciclo de vida explícito). |

### Exceções

| Classe | Quando é lançada |
|---|---|
| `EBeanException` | Falha ao empacotar/desempacotar bean ou cast inválido. |
| `EIoCBeanNotFoundException` | Base para beans não encontrados. |
| `ESingletonNotFoundException` | `GetSingleton` sem registro prévio no container global. |
| `EScopedNotFoundException` | Reservado. |

---

## Limitações Técnicas

- **Sem detecção de dependência circular:** se `A` depende de `B` e `B` depende de `A` dentro dos callbacks de fábrica, ocorrerá um loop infinito ou estouro de pilha. A detecção e quebra desse ciclo é responsabilidade do desenvolvedor.

- **Registro apenas por tipo + qualificador:** a identidade de um bean é formada exclusivamente pelo nome do `TypeInfo` e pelo qualificador. Não há suporte a atributos, anotações ou convenções de nomenclatura automáticas.

- **Singleton precisa de registro explícito no container global:** o escopo `Singleton` não é auto-registrado via `TIoCRegistry`. Beans singleton precisam ser registrados manualmente no `TSingletonBeanContainerHolder` interno ou via um container de sessão dedicado ao escopo global antes de serem resolvidos.

- **Thread safety não garantida:** `TIoCRegistry` e `TCallbackBeanFactory` utilizam `TDictionary` sem sincronização. Registros devem ocorrer no thread principal antes da criação de qualquer container. Containers de sessão não devem ser compartilhados entre threads.

- **`TBean.Close()` não implementado:** o método existe como ponto de extensão futuro, mas atualmente não executa nenhuma lógica de liberação explícita de recursos.

- **Apenas interfaces e classes via RTTI:** `Unwrap<T>` suporta `tkInterface` (via `Supports`) e `tkClass` (via `TValue.Cast`). Tipos primitivos, records e outros `TTypeKind` não são tratados e resultarão em comportamento indefinido.

- **Sem suporte a decorators ou interceptors:** não há mecanismo nativo para envolver beans com proxies, logging automático ou AOP.

- **Sem arquivo de configuração externo:** todo o registro é feito em código. Não há suporte a XML, JSON ou injeção por convenção.

---

## Licença

Veja o arquivo [LICENSE](LICENSE).
