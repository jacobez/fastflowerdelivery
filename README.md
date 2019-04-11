# Fast Flower Delivery

## Actors

### Flower Shop

#### Events

##### order placed

###### Attributes

- **customer_location**
- **delivery_due**

##### bid placed

###### Attributes

- **driver_id**
- **driver_location**

##### bid confirmed

###### Attributes

- **driver_id**
- **order_id**

##### delivery confirmed

###### Attributes

- **order_id**
- **time_delivered**

### Driver

#### Events

##### bid requested

###### Attributes

- **order_id**
- **shop_location**
- **customer_location**
- **pickup_available**
- **delivery_due**

##### delivery completed

###### Attributes

- **order_id**
