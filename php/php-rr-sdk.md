# PHP-SDK proposal
The dynamic nature of PHP provides a wide range of possibilities how workflows can be defined or dynamically generated.
A large variety of instruments, language performance and ease of use opens a lot of possibilities in a field of high-throughput, easy-to-develop
distributed applications. Since PHP 5.5 we can use [cooperative multitasking](https://nikic.github.io/2012/12/22/Cooperative-multitasking-using-coroutines-in-PHP.html) 
which can perfectly align with the workflow execution model.

## Table of Contents
- [Activities](#activities)
    - [Registration](#registration)
    - [Using Annotations](#using-annotations)
    - [Logging](#logging)
    - [Payloads](#payloads)
    - [Process Isolation](#process-isolation)
- [Workflows](#workflows)
    - [Registration](#registration-1)
    - [Using Annotations](#using-annotations-1)
    - [Syntax and Atomic Blocks](#syntax-and-atomic-blocks)
    - [Queries](#queries)
    - [Signals](#signals)
    - [Sessions](#sessions)
    - [Deterministic Time](#deterministic-time)
    - [Side Effects](#side-effects)
    - [Error Handling](#error-handling)
    - [Termination and Cancel Requests](#termination-and-cancel-requests)
- [Examples](#examples)
- [Service RPC](#service-rpc)
- [Implementation](#implementation)
    - [Features](#features)
    - [Milestones](#milestones)
- [Development](#development)

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
use Temporal\Workflow;

class UploadWorkflow
{
    public function run(Workflow\ContextInterface $ctx, string $input): string
    {
        $promise = yield new Workflow\ExecuteActivy(
            'activityName',
            $input, 
            100 // startToFinishTimeout, etc. 
        );        
    
        $result = yield $promise->get(Obj::class);

        return $result->getValue();
    }
}
```

Read more about proposed syntax approach and syntax sugar down below. The given example can be simplified into:

```php
use Temporal\Workflow;

class UploadWorkflow extends Workflow\Workflow
{
    public function run(string $input): string
    {
        $result = yield $this->activities
            ->withStartToFinish(100)
            ->activityName($input)
            ->get(Obj::class);

        return $result->getValue();
    }
}
```

> No common interface required.

### Registration
Similar to activities each workflow type must be registered within worker context, since worklow might expose more that 
one method (query, primary method) meta declation is required. 

```php
$worker = new WorkflowWorker();

$workflow = (new WorkflowDeclaration('name'))
                ->setClass(WofkflowClass::class)
                ->setHandlerMethod('run')
                ->addQueryHandler('name', 'method-name')
                ->addSignalHandler('name', 'method-name');

$worker->addWorkflow($workflow);
```

### Using Annotations
In more advanced frameworks it should be possible to register workflows using annotations or attributes.

```php
use Temporal\Workflow\Annotation as Temporal;

/**
 * @Temporal\Workflow(name="name", handler="run")
 */
class Workflow 
{
    public function run(ContextInterface $ctx, string $input): string
    {
        // ...   
    }

    /**
     * @Workflow\QueryMethod(name="something")
     */
    public function querySomething(string $world): string 
    {
        // ...
    }
    
    /**
     * @Workflow\SignalMethod(name="someSignal")
     */
    public function handleSignal(string $input): string 
    {
        // ...
    }
}
``` 

> The actual annotation format is TBD as it irrelevant to the implementation and might vary from framework to framework. 

### Syntax and Atomic Blocks
The building blocks of workflow is `yield` commands which might return actual value or a promise for this value. Every
command wrapped via dedicated class:

```php
function run()
{
    yield new Activity('name', 'values', [/* options */]);
}
```

Some commands might automatically return sub-commands. For example blocking activity execution:

```php
$result = yield (new Activity('name', 'values', [/* options */]))->get();
```

To wait for multiple activities at the same time we can introduce higher level promises such as:

```php
$a = yield new Activity('a', 'values', [/* options */]);
$b = yield new Activity('b', 'values', [/* options */]);

yield new WaitAll($a, $b);

// or 
yield new WaitAny($a, $b);
```

> More atomic blocks can be added down the road.

#### Syntax Sugar
It should be possible to mock `new Activity` and other commands with shorted methods from abstract workflow implementation:

```php
class MyWorkflow extends Workflow 
{
    public function run()
    {
        $result = yield $this->activities->doSomething()->get();
        yield $this->sleep(1);

        // ...
    }
}
``` 

### Queries
Workflow queries can be easily implemented using dedicated query method of workflow. The state of the workflow can be 
extracted from the properties of the object.

```php
use Temporal\Workflow;

class DemoWorkflow extends Workflow\Workflow
{
    private $step = 0;

    public function queryStep(): int 
    {
        return $this->step;
    }

    public function run(string $input): string
    {
        yield $this->activities->doSomething($input);
        $this->step++;

        // ...
    }
}
```

> Query methods must be registered explicitly.

An alternative approach can be based on registering the callback function during the workflow execution:

```php
yield new QueryHandler('something', function() use (&$step) {
    return $step;
});
```

> Such an approach is more suitable for dynamic workflows. The principle of work is identical to pre-registered queries.

#### Using Annotations
For more advanced frameworks it should be possible to register query method using annotation or attribute (PHP8) as 
in Java SDK.

```php
/**
 * @Workflow\QueryMethod(name="something")
 */
public function querySomething(string $world): string 
{
    return 'hello';
}
```

### Signals
Unlike queries the signals are fist-class citizen of actual workflow code. Unlike activities the signal can be triggered
at any moment, without prior expectation by workflow. 

Signal method can be defined explicitly:

```php
class UploadWorkflow extends Workflow\Workflow
{
    /** @Temporal\SignalMethod(name="signal") */
    public function handleSignal($input):void
    {
    
    }

    public function run(string $input): string
    {
        
    }
}
```

Or at runtime:

```php
public function run(string $input): string
{
    yield new SignalHandler('name', function($input){
    
    });       
}
```

> Need Temporal authors feedback.

#### Handle Signals
Incoming signals can be handled during any workflow `yield` call. Workflow should allow to explicitly wait for signal:

```php
public function run(string $input): string
{
    yield new SignalHandler('name', function($input){
        // do something
    });       

    yield new WaitSignal('name');
}
```

### Sessions
Sessions can be created as sub-activity group, using similar approach as `withTimeout` and other methods. However,
the explicit yield required. 

```php
public function run(string $input): string
{
    $session = yield $this->activities->createSession(100, 100); // timeouts
    
    $result = yield $session->doSomething($input)->get();
    $result = yield $session->somethingElse($result)->get();
    
    yield $session->complete();
    
    return $result;
}
```

### Deterministic Time
Workflows must avoid calling SPL functions `time()` and `date()`. Context method must be used instead:

```php
$ctx->getNow(); //DateTimeImmutable object.
```

#### Sleeps
Workflow can sleep using simple command returning promise:

```php
yield $this->sleep(1)->wait();

// or as promise
$t = yield $this->sleep(1);

yield new AnyOf($t, $this->activities->doSomething());
```

### Side Effects
Similar to Golang SDK the side effects can be registered using yield call:

```php
$result = yield new SideEffect(function(){
    return mt_rand(0, 1000);
});
```

Using syntax sugar (point of discussion):

```php
$result = yield $this->sideEffect(function(){
    return mt_rand(0, 1000);
});
```

> Similar to other SDKs, PHP version **does not** guarantee that sideEffect won't be called again during the replay. 

### Error Handling
Like in Java version of Temporal SDK the workflow errors can be delivered in form of exceptions triggered on `yield`:

```php
public function run(string $input): string
{
    try {
        return yield $this->activities->doSomething($input)->get();
    } catch (ActivityException $e) {
        // get related activity ID
        $this->logger->warning(
            "Activity %s failed with %s",
            $e->getActivityID(),
            $e->getMessage()
        );       
    }
}
``` 

Other errors can be triggered on workflow engine level, protocol error, etc. Exceptions must be diveded into following groups:

Exception Type | Parent | Comment 
--- | --- | ---
EngineException | - | Low level exception, usually local.
StalledException | EngineException | Triggered to indicate the workflow processing should stop (see below).
WorkflowException | EngineException | Generic workflow error (like activity can not be created and etc)
TimeoutException | WorkflowException | Workflow timed out (must contain information about actual timeout type). 
TerminateException | WorkflowException | Workflow needs to be terminated.
ActivityException | WorkflowException | Processing errors.
ActivityTimeoutException | ActivityException | Activity processing timeouted (must contain information about actual timeout type). 

> The exception tree is a subject of discussion. 

### Termination and Cancel Requests
The termination, cancel and stalled requested will be supplied to the workflow in a form of exceptions on `yield` call.
Similar to activity errors workflow can handle these exceptions and perform a proper rollback.

```php
public function run(string $input): string
{
    $step = 0;
    try {
        $resultA = yield $this->activities->doA($input)->get();
        $step++;
        
        $resultB = yield $this->activities->doB($resultA)->get();
        $step++;

        return yield $this->activities->doC($resultB)->get();
    } catch (CancellationException $e) {
        switch ($step) {
            case 2:
                yield $this->activities->rollbackB($resultB);
                // no break
            case 1:
                yield $this->activities->rollbackA($resultA);
        }
    
        throw $e;   
    }
}
```

> The `StalledException` or `PauseException` (TBD) used to notify the workflow that code must be offloaded from memory
> (cache) without cancelling any activity.

## Examples
Following examples demonstrates features described above in a more realistic scenarios.

### Simple Subscription Workflow
```php
class SubscriptionWorkflow extends Workflow
{
    public function subscriptionWorkflow(string $customerID)
    {
        yield $this->activities->onboardFreeTrial($customerID);
        
        try {
            yield $this->sleep(60 * Time::DAY);
            yield $this->activities->upgradeFromTrialToPaid($customerID);
    
            while(true) {
                yield $this->sleep(30 * Time::DAY);
                yield $this->activities->chargeMonthlyFee($customerID);
            }       
        }
        catch (CancellationException $e) {
            yield $this->activities->cancelSubscription($customerID);
        }
    }
}
```

### Daily charge using points and then credit card
The workflow provides the ability to accumulate points using signals. You can run one worflow like that per
customer.

```php
class ServiceUsageWorkflow extends Workflow
{
    private $points = 0;

    /** @Workflow\QueryMethod(name="points") */
    public function getPoints(): int
    {
        return $this->points;
    }

    /** @Workflow\SignalMethod(name="points") */
    public function addPoints(int $points)
    {
        $this->points += $points;
    }

    /** @Workflow(name="serviceUsage") */
    public function run(string $customerID)
    {
        try {
            while(true) {            
                 yield $this->sleep(Time::DAY); 
                
                // must charge customer
                if ($this->points > 0) {
                    $this->points--;
                } else {           
                    yield $this->activities->chargeDailyUsage($customerID);
                    yield $this->activities->prolongAccess($customerID);
                }
            } 
        }
        catch (CancellationException $e) {
            yield $this->activities->cancelAccess($customerID);
            yield $this->activities->cancelSubscription($customerID);
        }
    }
}
```

## Service RPC
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

## Implementation
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
