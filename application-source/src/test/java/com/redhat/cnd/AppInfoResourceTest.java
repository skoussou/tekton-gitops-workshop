package com.redhat.cnd;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;

@QuarkusTest
public class AppInfoResourceTest {

    @Test
    public void appInfoEndpoint() {
        given()
          .when().get("/app/info")
          .then()
             .statusCode(200)
             .body(is("local_test - quarkus-app:test"));
    }

}