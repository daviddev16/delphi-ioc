# delphi-ioc

Uma biblioteca leve de **Inversão de Controle (IoC)** e **Injeção de Dependência (DI)** para Delphi, baseada em um modelo de fábrica com callbacks e suporte a escopos de ciclo de vida de beans.

## Introdução

A premissa central do delphi-ioc é que tanto a **criação** quanto a **definição de escopo** das dependências sejam transparentes para quem consome o container.

Na maioria das bibliotecas de IoC, o container age como um catálogo de objetos vivos: instâncias são criadas, armazenadas na memória e entregues ao chamador. O delphi-ioc inverte esse ponto de vista. Em vez de gerenciar objetos em memória de forma opaca, você **define o fluxo de criação** — ou seja, registra callbacks que descrevem *como* cada dependência deve ser construída e *quais* outras dependências ela precisa. O container executa esse fluxo somente quando necessário, de acordo com o escopo solicitado.

Isso tem algumas consequências práticas importantes:

**A construção permanece no seu código.** O `Create` nunca desaparece; ele continua explícito dentro do callback de fábrica, onde você tem controle total sobre os parâmetros, condicionais e tratamento de erros da criação.

**O escopo é uma decisão de registro, não do objeto.** Ao registrar uma factory, você já define se ela produz beans scoped, singleton ou transient. O objeto em si não sabe — e não precisa saber — qual é o seu ciclo de vida.

**Não há mágica por reflexão ou atributos.** O registro é feito em código puro, sem varredura de assemblies, sem atributos de injeção e sem convenções implícitas. O que está escrito é o que acontece.

O resultado é um container que serve como **organizador de dependências** — não como um framework que assume o controle da construção dos seus objetos.

---

## Sumário

- [Instalação](#instalação)
- [Início Rápido](#início-rápido)
- [Registrando Dependências](#registrando-dependências)
- [Escopos de Ciclo de Vida](#escopos-de-ciclo-de-vida)
  - [Scoped](#scoped)
  - [Singleton](#singleton)
  - [Transient](#transient)
- [Qualificadores](#qualificadores)
- [Injeção de Instâncias Externas](#injeção-de-instâncias-externas)
- [Interceptors e Proxy](#interceptors-e-proxy)
- [Referência da API](#referência-da-api)
- [Conceitos](#conceitos)
- [Limitações Técnicas](#limitações-técnicas)
- [Recursos Futuros](#recursos-futuros)

---

## Instalação

Adicione `IoC.pas` e `IoC.Proxy.pas` ao seu projeto ou ao Search Path do Delphi. Não há dependências externas além da RTL padrão.

---

## Início Rápido

O exemplo abaixo mostra o fluxo completo: registrar factories, criar um container de sessão e resolver uma dependência.

```delphi
program MeuApp;

{$APPTYPE CONSOLE}

uses
  IoC, IoC.Proxy, Examples;

begin
  // 1. Registrar factories uma única vez na inicialização da aplicação
  TIoCRegistry
    .RegisterScopedBeanFactory<IConnectionProvider>(
      function(Ctx: TScopedBeanFactoryContext): TBeanValue
      begin
        Result := TConnectionProvider.Create();
      end)

    .RegisterScopedBeanFactory<IProductRepository>(
      function(Ctx: TScopedBeanFactoryContext): TBeanValue
      begin
        // Injeta IConnectionProvider do mesmo escopo de sessão
        Result := TProductRepository.Create(Ctx.Scoped<IConnectionProvider>());
      end);

  // 2. Criar um container por sessão/request
  var Container := TSessionBeanContainer.Create();
  var Repo := Container.GetScoped<IProductRepository>();
  WriteLn('Total de produtos: ', Repo.Count());

  Container.Free();
end.
```

Saída esperada:

```
Called: TConnectionProvider.Create
Called: TProductRepository.Create
Total de produtos: 1000
Called: TProductRepository.Destroy
Called: TConnectionProvider.Destroy
```

---

## Registrando Dependências

Todo registro é feito globalmente em `TIoCRegistry` antes de qualquer container ser criado. O escopo é definido no momento do registro, não na resolução.

O registro é **encadeável** — cada chamada retorna `TIoCRegistry`, permitindo múltiplos registros em uma única expressão:

```delphi
TIoCRegistry
  .RegisterScopedBeanFactory<IServicoA>(factoryA)
  .RegisterScopedBeanFactory<IServicoB>(factoryB)
  .RegisterSingletonBeanFactory<IConfig>(factoryConfig);
```

O callback de fábrica recebe um contexto (`Ctx`) que permite resolver outras dependências do mesmo container durante a construção:

| Escopo do registro | Tipo do contexto | Métodos disponíveis no contexto |
|---|---|---|
| Scoped / Transient | `TScopedBeanFactoryContext` | `Scoped<T>`, `Transient<T>`, `Singleton<T>` |
| Singleton | `TSingletonBeanFactoryContext` | `Singleton<T>` |

O contexto de um singleton é propositalmente restrito: um singleton só pode depender de outros singletons, evitando que um objeto de vida longa capture dependências de escopo curto.

---

## Escopos de Ciclo de Vida

### Scoped

O bean é criado na primeira resolução dentro de uma sessão e **reutilizado** em todas as resoluções subsequentes do mesmo container. Quando o container é destruído, as referências são liberadas.

```delphi
TIoCRegistry.RegisterScopedBeanFactory<IMinhaInterface>(
  function(Ctx: TScopedBeanFactoryContext): TBeanValue
  begin
    Result := TMinhaClasse.Create();
  end);

// Mesma instância dentro do Container
var A := Container.GetScoped<IMinhaInterface>();
var B := Container.GetScoped<IMinhaInterface>();
// A e B apontam para o mesmo objeto
```

**Ideal para:** conexões de banco de dados, contextos de unidade de trabalho (Unit of Work), objetos caros por request/sessão.

---

### Singleton

O bean é criado na primeira resolução em toda a aplicação e **compartilhado por todos os containers**. A criação é lazy e thread-safe: o singleton só é instanciado quando alguém o solicita pela primeira vez, e chamadas concorrentes aguardam sem criar instâncias duplicadas.

```delphi
TIoCRegistry.RegisterSingletonBeanFactory<IAppConfig>(
  function(Ctx: TSingletonBeanFactoryContext): TBeanValue
  begin
    Result := TAppConfig.LoadFromFile('config.ini');
  end);

// Mesma instância em qualquer container, em qualquer thread
var Cfg := Container.GetSingleton<IAppConfig>();
```

**Ideal para:** configurações globais, caches de aplicação, serviços sem estado.

---

### Transient

Um novo bean é **criado a cada resolução**, sem qualquer reuso ou cache.

```delphi
TIoCRegistry.RegisterScopedBeanFactory<IMinhaInterface>(
  function(Ctx: TScopedBeanFactoryContext): TBeanValue
  begin
    Result := TMinhaClasse.Create();
  end);

var A := Container.GetTransient<IMinhaInterface>();
var B := Container.GetTransient<IMinhaInterface>();
// A e B são instâncias distintas
```

**Ideal para:** objetos leves, comandos, handlers de curta duração.

> Os escopos Scoped e Transient compartilham o mesmo registro (`RegisterScopedBeanFactory`). A distinção acontece na resolução: `GetScoped` reutiliza, `GetTransient` sempre cria.

---

## Qualificadores

Quando é necessário registrar múltiplas implementações de um mesmo tipo, use um qualificador string para diferenciar:

```delphi
TIoCRegistry
  .RegisterScopedBeanFactory<ILogger>('console',
    function(Ctx: TScopedBeanFactoryContext): TBeanValue
    begin
      Result := TConsoleLogger.Create();
    end)

  .RegisterScopedBeanFactory<ILogger>('file',
    function(Ctx: TScopedBeanFactoryContext): TBeanValue
    begin
      Result := TFileLogger.Create();
    end);

var ConsoleLog := Container.GetScoped<ILogger>('console');
var FileLog    := Container.GetScoped<ILogger>('file');
```

---

## Injeção de Instâncias Externas

É possível registrar manualmente uma instância já criada no escopo de um container, sem passar pela factory. Útil para injetar objetos construídos fora do container — como mocks em testes ou objetos criados por frameworks externos.

```delphi
var MockRepo := TProductRepositoryMock.Create();
Container.InjectScoped<IProductRepository>('mock', MockRepo);

// A partir daqui, GetScoped retorna o mock
var Repo := Container.GetScoped<IProductRepository>('mock');
```

---

## Interceptors e Proxy

O delphi-ioc suporta **interceptors** para interfaces, permitindo envolver qualquer bean com comportamento transversal (logging, métricas, cache, validação) sem alterar a implementação original.

Um interceptor implementa `IInterceptor` e recebe uma cadeia de invocação que representa a chamada original ao método. Ele pode executar lógica antes e depois, modificar argumentos ou resultados, e decidir se passa a chamada adiante.

```delphi
type
  TProductRepositoryLoggerDecorator = class(TInterfacedObject, IInterceptor)
  public
    procedure Handle(const Chain: TProxyInvokeChain);
  end;

procedure TProductRepositoryLoggerDecorator.Handle(const Chain: TProxyInvokeChain);
begin
  WriteLn('Chamando >> ' + Chain.Method.Name);
  try
    Chain.Proceed();  // executa o método real
  finally
    WriteLn('Resultado >> ' + Chain.Result.ToString());
  end;
end;
```

Os interceptors são registrados junto com a factory, como uma lista passada ao final do registro:

```delphi
TIoCRegistry
  .RegisterScopedBeanFactory<IProductRepository>(
    function(Ctx: TScopedBeanFactoryContext): TBeanValue
    begin
      Result := TProductRepository.Create(Ctx.Scoped<IConnectionProvider>());
    end,
    [TProductRepositoryLoggerDecorator.Create()]  // <- interceptors
  );
```

Quando o bean for resolvido, o container entrega automaticamente um proxy que intercepta todas as chamadas de interface antes de delegá-las ao objeto real. O código que consome `IProductRepository` não sabe e não precisa saber que há um interceptor ativo.

---

## Referência da API

### `TSessionBeanContainer`

| Método | Descrição |
|---|---|
| `GetScoped<T>()` | Resolve o bean do escopo da sessão. Cria na primeira chamada e reutiliza nas seguintes. |
| `GetScoped<T>(Qualifier)` | Idem, com qualificador. |
| `GetTransient<T>()` | Cria uma nova instância a cada chamada, sem cache. |
| `GetTransient<T>(Qualifier)` | Idem, com qualificador. |
| `GetSingleton<T>()` | Resolve do container global. Lança exceção se não houver factory registrada. |
| `GetSingleton<T>(Qualifier)` | Idem, com qualificador. |
| `InjectScoped<T>(Qualifier, Instance)` | Registra uma instância já existente diretamente no escopo da sessão, sem passar pela factory. |

### `TProxy`

| Método | Descrição |
|---|---|
| `CreateProxyFor<T>(Thing, Interceptors)` | Envolve uma instância existente com um array de interceptors. Retorna um proxy tipado. |
| `CreateProxyFor<T>(Thing, Interceptor)` | Idem, com um único interceptor. |
| `CreateStub<T>(Interceptor)` | Cria um proxy sem implementação real. Todas as chamadas passam pelo interceptor. |
| `CreateStub<T>(Interceptors)` | Idem, com múltiplos interceptors. |

**Proxy sobre uma instância existente:**

```delphi
// Envolve um objeto real com um único interceptor
var Repo := TProductRepository.Create(Connection);
var ProxiedRepo := TProxy.CreateProxyFor<IProductRepository>(Repo, TLoggerInterceptor.Create());

// Ou com múltiplos interceptors encadeados
var ProxiedRepo := TProxy.CreateProxyFor<IProductRepository>(Repo,
  [TLoggerInterceptor.Create(),
   TMetricsInterceptor.Create()]);
```

Cada chamada a `ProxiedRepo.Count()` passará pelos interceptors na ordem declarada antes de chegar ao objeto real. O interceptor chama `Chain.Proceed()` para avançar para o próximo da cadeia.

**Stub — proxy sem implementação real:**

Útil em testes onde você quer controlar totalmente o retorno de cada método sem criar uma implementação concreta.

```delphi
type
  TProductRepositoryStub = class(TInterfacedObject, IInterceptor)
  public
    procedure Handle(const Chain: TProxyInvokeChain);
  end;

procedure TProductRepositoryStub.Handle(const Chain: TProxyInvokeChain);
begin
  if Chain.Method.Name = 'Count' then
    Chain.SetResult(TValue.From<Integer>(42));
  // métodos não tratados retornam valor padrão
end;

// Cria um proxy sem nenhuma classe por trás
var Stub := TProxy.CreateStub<IProductRepository>(TProductRepositoryStub.Create());
WriteLn(Stub.Count()); // 42
```

**Acessando o objeto real dentro do interceptor:**

O `Chain` expõe o objeto original através de `ThingAs<T>`, caso o interceptor precise inspecioná-lo diretamente.

```delphi
procedure TMeuInterceptor.Handle(const Chain: TProxyInvokeChain);
var
  Repo: IProductRepository;
begin
  Repo := Chain.ThingAs<IProductRepository>();
  // inspeciona ou usa Repo antes de delegar
  Chain.Proceed();
end;
```

---

## Conceitos

| Termo | Descrição |
|---|---|
| **Bean** | Qualquer objeto gerenciado pelo container IoC. |
| **Registry** | Ponto central onde as factories globais são registradas. |
| **Container** | Resolve e mantém beans dentro de um escopo de sessão. |
| **Factory Callback** | Função anônima que descreve como criar um bean. |
| **Contexto de Fábrica** | Parâmetro do callback que permite resolver outras dependências durante a construção. |
| **Interceptor** | Componente que envolve um bean para adicionar comportamento transversal. |
| **Proxy** | Wrapper gerado dinamicamente que direciona chamadas de interface pelos interceptors. |
| **Stub** | Proxy sem implementação real, construído apenas com interceptors. |

---

## Limitações Técnicas

- **Sem detecção de dependência circular:** se `A` depende de `B` e `B` depende de `A` dentro dos callbacks de fábrica, ocorrerá um loop infinito ou estouro de pilha. A detecção e quebra desse ciclo é responsabilidade do desenvolvedor.

- **Registro apenas por tipo + qualificador:** a identidade de um bean é formada exclusivamente pelo nome do tipo e pelo qualificador. Não há suporte a atributos, anotações ou convenções de nomenclatura automáticas.

- **Resolução estrita por tipo exato:** registrar uma factory para `IProductRepository` e resolver via `TAbstractProductRepository` — mesmo que seja uma atribuição válida em tempo de compilação — resultará em erro, pois as identidades são distintas. O container não faz inferência de compatibilidade entre tipos.

- **Thread safety parcial:** o escopo singleton tem proteção de leitura e escrita concorrente. Containers de sessão (`TSessionBeanContainer`) e o registro global não são thread-safe e não devem ser compartilhados entre threads. Registros devem ocorrer no thread principal antes da criação de qualquer container.

- **`TBean.Close()` não implementado:** o método existe como ponto de extensão futuro, mas atualmente não executa nenhuma lógica de liberação explícita de recursos.

- **Apenas interfaces e classes:** o sistema de unwrap e proxy suporta interfaces e classes. Tipos primitivos, records e outros tipos de valor não são tratados.

- **Proxy requer interface com GUID:** para criar um proxy ou stub, a interface precisa ser declarada como `IInvokable` ou ter um GUID explícito. Interfaces sem GUID causarão erro em tempo de execução.

- **Sem arquivo de configuração externo:** todo o registro é feito em código. Não há suporte a XML, JSON ou injeção por convenção.

---

## Recursos Futuros

- **Factory via RTTI:** uma implementação alternativa que usa reflexão para instanciar beans automaticamente, inspecionando construtores e resolvendo parâmetros pelo tipo. Mantém compatibilidade com o modelo atual de callbacks — os dois podem coexistir — mas elimina o boilerplate de registro para casos onde a convenção é suficiente.

- **Logger de diagnóstico:** suporte a um logger no container para registrar eventos de criação e recuperação de beans por escopo. Útil para entender a ordem de resolução das dependências, identificar beans criados mais vezes do que o esperado e rastrear o ciclo de vida durante o desenvolvimento.

- **Resolução por tipo base ou classe ancestral:** um mecanismo de resolução por compatibilidade de tipo está planejado para cobrir cenários onde o tipo solicitado é compatível por atribuição com o tipo registrado, mas difere em identidade.

- **Detecção de dependência circular:** verificação em tempo de resolução do grafo de dependências para identificar ciclos antes que causem estouro de pilha, com uma exceção descritiva indicando a cadeia que formou o ciclo.

---

## Licença

Veja o arquivo [LICENSE](LICENSE).
