# PHP-SDK proposal
The dynamic nature of PHP provides a wide range of possibilities how workflows can be defined or dynamically generated.
A large variety of instruments, language performance and ease of use opens a lot of possibilities in a field of high-throughput, easy-to-develop
distributed applications. Since PHP 5.5 we can use [cooperative multitasking](https://nikic.github.io/2012/12/22/Cooperative-multitasking-using-coroutines-in-PHP.html) 
which can perfectly align with the workflow execution model.

## Table of Contents
- Activities
    - Registration
    - Using Annotations
    - Payloads
    - Process Isolation
- Workflows
    - Registration
    - Syntax
    - Queries
    - Sessions
- Service RPC
- Implementation
    - Features
    - Milestones
- Development

## Activities
Similar to other SDKs, the Activity implementation in PHP won't have any feasible limitations. Is it possible to invoke 
any callable function, object method or anonymous function. The invocation arguments can be hydrated based on provided
payload using [method reflection](https://www.php.net/manual/en/class.reflectionfunctionabstract.php) mechanism provided by php.    

The invocation context and heartbeats could be addressed `ContextInterface` object. The error handling done using classic
PHP exceptions.

```php
function processFile(string $url): string
{
    $result = doSomeWork($url);

    return $result;
}
```

Heartbeat example:

```php
use Temporal\Workflow\ContextInterface;
use Temporal\Workflow\Activity;

// parameter order does not matter
function downloadFile(ContextInterface $ctx, string $url)
{
    $downloader = new FileDownloader();
    $downloader->onProgress(function($progress) use($ctx){
        // subject of discussion
        Activity::heartbeat($ctx, $progress);
    });

    return $downloader->download($url);
}
```

Alternatively we can embed the heartbeat method directly into `ContextInterface` or `ActivityContextInterface`:

```php
use Temporal\Workflow\ActivityContextInterface;

// parameter order does not matter
function downloadFile(ActivityContextInterface $ctx, string $url)
{
    $downloader = new FileDownloader();
    $downloader->onProgress(function($progress) use($ctx){
        // subject of discussion
        $ctx->heartbeat($progress);
    });

    // for external activities
    dump($ctx->getTaskToken());

    return $downloader->download($url);
}
```

The second approach deviate from a read-only concept of contexts but makes testing much easier.

### Registration
Activities can be registered in corresponding workers. Since workflows will run in different process there are no need to
mix two abstractions together:

```php
$worker = new Activities();
$worker->register('activity.name', 'functionName');

// for objects
$worker->register('activity.name2', [$object, 'methodName']);

// blocking
$worker->run(new RoadRunner\Worker(...));
```

> It might be beneficial to provide underlying registry abstraction to simplify the coding of workflows. See the
> example below.

### Using Annotations
In a more sophisticated frameworks, some activities can be detected and registered automatically using static analysis
of codebase and annotations. No common interface required.

```php
class FileController 
{
    /**
     * @Workflow\Activity("name" = "file.download") 
     */         
    public function processFile(string $file): string 
    {
        $result = $this->doProcessing($file);

        return $result;
    }

    // ...
}
```

> PHP 8 annotations or alternative registration methods possible as well.

### Logging
It is possible to provide access to log stream from the `ActivityContextInterface` which makes possible to use PSR-3 compatible
loggers.

```php
$logger = new ActivityLogger($ctx);
$logger->debug('Hello!');

// or directly
$ctx->log('debug', 'message', ['context']);
```

### Payloads
The payloads and responses can be serialized and deserialized to the target format using simple type reflection. 
Such an approach makes possible to use PHP objects as data carrying medium:

```php
class MyObj 
{
    public string $something;
}

function doSomething(ActivityContextInterface $ctx, MyObj $input): Response
{
  // ...
    return new Response('something');
}
```

It is mandatory to use proper type declarations on input and return types of activity. While PHP 7.4 is not widely adopted,
it is recommended to use strict property typing for payload properties as well when possible or highlight the type via
mapper specific annotation.

### Process Isolation
Activity handler will stay in memory permanently, only the execution context will change. Such an approach will ellimitate 
the framework initialization overhead and reduce memory consumption. 

The system must limit to only one concurrent execution per worker, which makes possible to use all existing PHP SPL and vendor
libraries without changes. 

## Workflows
Unlike activities, the workflow execution must be based on a physical memory object. In order to ensure proper density
and effectiveness of the system, multiple workflows will locate inside singe PHP process. Each workflow will operate
as one or multiple [Generators](https://www.php.net/manual/en/class.generator.php). The execution can be controlled using
system [keyword](https://www.php.net/manual/en/language.generators.syntax.php) `yield`.

Yield keyword should be used to request the command execution by Temporal system. For the sake of simplify each command
must be presented as typed object, though, end user API can encapsulate object construction using helper functions. 

Each yield command will return Promise/Future object which can later be referenced in a code. Simple workflow execution might
look as following:

```php
class UploadWorkflow
{
    public function run($in) // context to get time and etc?
    {
        $a = yield $this->downloadURL('x', 'a');
        $b = yield $this->process($in);

        // syntax sugar?
        yield new Workflow\WaitAll($a, $b);

        // blocking Get atomic?
        return yield ($this->sendEmail($result))->get(new Obj());
    }
}
```

> No common interface is required.

### Registration

### Syntax

### Queries

### Signals

### Sessions


### Service RPC
The Temporal service SDK in PHP can be written as simple RPC bridge to Golang SDK. This section is pretty straight forward
and does not require much explanation.

```php
use Temporal\Workflow\Service;

// ...

public function doSomething(Service $service)
{
    $service->startWorkflow("workflowName", ["payload"], ...);
}

// ...
```

> Same client can be used to control the state and heartbeats of external activities. 

## Implementation Details
We propose to implement the SDK as module of [RoadRunner](https://github.com/spiral/roadrunner) application server. The server
written in Golang, tested on production and currently includes all the functions needed to run PHP effectively inside the
Golang application. 
 
### Features
A number of features expected to be implemented in this SDK in order to utilize the scripting nature of PHP efficiently.

#### Performance
One of the side effects of the RoadRunner execution model is the ability to keep PHP process in memory
indefinitely. Unlike classic PHP-FPM applications which recreate the process for each request it guarantees low overhead
and near maximum language [performance](https://www.techempower.com/benchmarks/#section=data-r0&hw=ph&test=fortune&l=zg24n3-f&c=4&a=2&o=e).

#### Plug In Play
Since all the Temporal communication encapsulated in application server the workflow coordination happens over plain
binary protocol between RR and PHP worker. Essentially, it completely eliminates the need to install any PHP extension, 
making integration non-invasive and more reliable.   

> Such an approach makes possible to implement workers in other languages as well (Python, JS) using same SDK.

#### Hot Reload
Due to the scripting nature of PHP it becomes possible to reload the workflow or activity code without stopping the worker (though, 
new SDK API required for workflows). Such an approach makes possible to perform hot deployment of workflow updates, debug
system on production and other things which are nearly impossible in compiled languages.  

### Milestones
A number of steps required to implement such SDK properly:
- receive stable API for Temporal Workflows on Golang (https://github.com/temporalio/temporal-go-sdk/commit/09ced59198a7e5a402ba463a8d11f2952c34dd5e)
- modernize RoadRunner to expose low level async API to communicate with PHP workers

After these steps complete, the implementation can start. 

## Development
The author of this proposal and his team ready to handle the implementation of this SDK for general purpose frameworks 
via RoadRunner module.
