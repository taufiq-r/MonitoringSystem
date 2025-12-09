#### Monitoring System ####

* fix cAdvisor failed mount docker-container
  * sudo -s 
  * create docker daemon.json

  * ```
     nano /etc/docker/daemon.json
  
     add this -> 
 	{
 	  "features": {
            "cdi": true,
    	    "containerd-snapshotter": false
      	    }
        }
    ```


  * edit docker.service
  * ``` systemctl edit docker.service
        add this -> [Service]
		    Environment=DOCKER_MIN_API_VERSION=1.24
     Before line  ### Edits below this comment will be discarded


    ```
  * after save file:
     run -> ```systemctl daemon-reload```
	       systemctl restart docker
 * exit root
 * Done 
