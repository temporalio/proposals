# PHP-SDK proposal
The dynamic nature of PHP provides a wide range of possibilities how workflows can be defined or dynamically generated.
A large variety of instruments, language performance and ease of use opens a lot of possibilities in a field of high-throughput 
distributed applications.

## Table of Contents
- Activities
    - Registration
    - Using Annotations
    - Payloads
    - Process Isolation
- Workflows
- Implementation Details
    - Features
    - Service RPC
    - Current Milestones
- Development  

## Activities
Similar to other SDKs the Activity implementation in PHP won't have any feasible limitations. Is it possible to invoke 
any callable function or object method. The invocation arguments can be hydrated based on provided payload using
[method reflection](https://www.php.net/manual/en/class.reflectionfunctionabstract.php) mechanism provided by php.    

The invocation context and heartbeats could be addressed `ContextInterface` object. The error handling done using classic
PHP exceptions.

```php
function downloadFile(string $url)
{
    return doDownload($url);
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

### Registration
Activities can be registered in corresponding workers. Since workflows will run in different workers there are no need to
mix two abstractions together:

```php
$worker = new Activities();
$worker->register('activity.name', 'functionName');

// for objects
$worker->register('activity.name2', [$object, 'methodName']);

// blocking
$worker->run(new RoadRunner\Worker(...));
```

It should be possible to provide third argument to define custom payload serializer/deserializer:

```php
$worker->register('my.activity', 'functionName', new JsonMarshaller());
```

### Using Annotations
In a more sophisticated frameworks some activities can be detected and registered automatically using static analysis
of codebase and annotations. No common interface required.

```php
class FileController 
{
    /**
     * @Workflow\Activity("name"="file.download") 
     */         
    public function downloadFile(string $file): string 
    {
        $result = doSomething();
        return $result;
    }
}
```

> PHP 8 annotations or alternative registration methods possible as well.

### Process Isolation
Activity handler will stay in memory permanently, only the context will change. Such an approach will reduce bootload
overhead and memory consumption. Only one activity can be executed in worker at moment of time to keep PHP share nothing
approach and make possible to use any classic PHP library. 

### Payloads
The payloads and responses can be serialized and deserialized to the target format using simple type reflection 
or alternatives (for example `GeneratedHydrator` by Ocranimus). Such an approach makes possible to use PHP objects as
data carrying medium:

```php
class MyObj 
{
    public string $something;
}

function doSomething(ContextInterface $ctx, MyObj $input)
{
  // ...
    return new Response('something');
}
```

## Workflows
:)

```php
class UploadWorkflow
{
    public function run() // context to get time and etc?
    {
        $a = yield $this->downloadURL('x', 'a');
        $b = yield $this->process($result);

        // syntax sugar?
        yield new Workflow\WaitAll($a, $b);

        return (yield $this->sendEmail($result))->get(new Obj());
    }
}
```

## Implementation Details

### Features
hot reload must

### Service RPC

### Current Milestones
A number of steps required to implement such SDK properly:
- receive stable API for Temporal Workflows on Golang (https://github.com/temporalio/temporal-go-sdk/commit/09ced59198a7e5a402ba463a8d11f2952c34dd5e)
- modernize RoadRunner to expose low level async API to communicate with PHP workers (in progress)
- implement SDK 

## Development
The author of this proposal and his team capable and ready to handle the implementation of this SDK for general purpose
frameworks running under RoadRunner.
