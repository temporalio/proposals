# Data Conversion

The Kotlin SDK uses `kotlinx.serialization` by default for JSON serialization. It provides compile-time safety, no reflection overhead, and native Kotlin support.

## kotlinx.serialization (Default)

Annotate data classes with `@Serializable`:

```kotlin
@Serializable
data class Order(
    val id: String,
    val items: List<OrderItem>,
    val status: OrderStatus
)

@Serializable
data class OrderItem(
    val productId: String,
    val quantity: Int
)

@Serializable
enum class OrderStatus { PENDING, PROCESSING, COMPLETED }
```

No additional configuration needed—the SDK automatically uses `kotlinx.serialization` for classes annotated with `@Serializable`.

### Custom JSON Configuration

```kotlin
val client = WorkflowClient(service) {
    dataConverter = KotlinxSerializationDataConverter {
        ignoreUnknownKeys = true
        prettyPrint = false  // default
        encodeDefaults = true
    }
}
```

### Polymorphic Types

For sealed classes and interfaces:

```kotlin
@Serializable
sealed class PaymentMethod {
    @Serializable
    @SerialName("credit_card")
    data class CreditCard(val number: String, val expiry: String) : PaymentMethod()

    @Serializable
    @SerialName("bank_transfer")
    data class BankTransfer(val accountNumber: String) : PaymentMethod()
}
```

### Custom Serializers

For types that need custom serialization:

```kotlin
@Serializable(with = BigDecimalSerializer::class)
data class Money(val amount: BigDecimal, val currency: String)

object BigDecimalSerializer : KSerializer<BigDecimal> {
    override val descriptor = PrimitiveSerialDescriptor("BigDecimal", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: BigDecimal) = encoder.encodeString(value.toPlainString())
    override fun deserialize(decoder: Decoder) = BigDecimal(decoder.decodeString())
}
```

## Jackson (Optional, for Java Interop)

For mixed Java/Kotlin codebases or when integrating with existing Jackson-based infrastructure:

```kotlin
val converter = DefaultDataConverter.newDefaultInstance().withPayloadConverterOverrides(
    JacksonJsonPayloadConverter(
        KotlinObjectMapperFactory.new()
    )
)

val client = WorkflowClient(service) {
    dataConverter = converter
}
```

> **Note:** Jackson requires the `jackson-module-kotlin` dependency and uses runtime reflection. Prefer `kotlinx.serialization` for pure Kotlin projects.

### Custom Jackson Configuration

```kotlin
val objectMapper = KotlinObjectMapperFactory.new().apply {
    configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
    registerModule(JavaTimeModule())
}

val converter = DefaultDataConverter.newDefaultInstance().withPayloadConverterOverrides(
    JacksonJsonPayloadConverter(objectMapper)
)
```

## Comparison

| Feature | kotlinx.serialization | Jackson |
|---------|----------------------|---------|
| Reflection | None (compile-time) | Required |
| Performance | Faster | Slower |
| Kotlin support | Native | Via module |
| Java interop | Limited | Excellent |
| Setup | `@Serializable` annotation | Automatic |
| Bundle size | Smaller | Larger |

## Recommendations

- **Pure Kotlin projects**: Use `kotlinx.serialization`
- **Mixed Java/Kotlin**: Consider Jackson for shared data types
- **Existing Jackson infrastructure**: Use Jackson for consistency

## Next Steps

- [KOptions](./koptions.md) - Configuration options
- [Interceptors](./interceptors.md) - Cross-cutting concerns
