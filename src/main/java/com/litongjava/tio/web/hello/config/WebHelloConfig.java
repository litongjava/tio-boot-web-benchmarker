package com.litongjava.tio.web.hello.config;

import nexus.io.annotation.AConfiguration;
import nexus.io.annotation.Initialization;
import com.litongjava.tio.web.hello.handler.HelloHandler;
import com.litongjava.tio.web.hello.handler.IndexHandler;

import nexus.io.tio.boot.server.TioBootServer;
import nexus.io.tio.http.server.router.HttpRequestRouter;

@AConfiguration
public class WebHelloConfig {

  @Initialization
  public void config() {

    TioBootServer server = TioBootServer.me();
    HttpRequestRouter requestRouter = server.getRequestRouter();

    HelloHandler helloHandler = new HelloHandler();
    IndexHandler indexHandler = new IndexHandler();
    requestRouter.add("/hello", helloHandler::hello);
    requestRouter.add("/plaintext", indexHandler::plaintext);
    requestRouter.add("/json", indexHandler::json);
  }
}
