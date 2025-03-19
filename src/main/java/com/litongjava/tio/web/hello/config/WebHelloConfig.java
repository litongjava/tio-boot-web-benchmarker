package com.litongjava.tio.web.hello.config;

import com.litongjava.annotation.AConfiguration;
import com.litongjava.annotation.Initialization;
import com.litongjava.tio.boot.server.TioBootServer;
import com.litongjava.tio.http.server.router.HttpRequestRouter;
import com.litongjava.tio.web.hello.handler.HelloHandler;
import com.litongjava.tio.web.hello.handler.IndexHandler;

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
